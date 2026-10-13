import AppKit

/// 应用程序图标缓存与获取管理器
public final class AppIconProvider: @unchecked Sendable {
    public static let shared = AppIconProvider()
    
    private let cache = NSCache<NSString, NSImage>()
    private let lock = NSLock()
    private var unresolvedBundleIDs = Set<String>()
    
    public init() {
        cache.countLimit = AppConstants.Storage.maxAppEntriesCount
    }
    
    /// 根据 Bundle Identifier 获取应用程序图标
    /// - Parameter bundleID: 目标应用程序的 Bundle Identifier（例如 "com.apple.dt.Xcode"）
    /// - Returns: 解析到的 NSImage，若应用未安装或未找到则返回 nil
    public func icon(for bundleID: String) -> NSImage? {
        let trimmed = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        let cacheKey = trimmed as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }
        
        // 检查负缓存：若先前已确认不存在该应用，直接快速返回 nil，杜绝主线程重复 IPC
        lock.lock()
        if unresolvedBundleIDs.contains(trimmed) {
            lock.unlock()
            return nil
        }
        lock.unlock()
        
        let targetSize = NSSize(
            width: AppConstants.UI.iconThumbnailSize,
            height: AppConstants.UI.iconThumbnailSize
        )
        
        // 1. 若应用处于运行状态，直接获取运行中实例的图标并转换为紧凑缩略图
        if let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: trimmed).first,
           let runningIcon = runningApp.icon {
            let thumbnail = createThumbnail(from: runningIcon, targetSize: targetSize)
            cache.setObject(thumbnail, forKey: cacheKey)
            return thumbnail
        }
        
        // 2. 若未运行，尝试通过 NSWorkspace 解析本地应用程序安装路径
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: trimmed) {
            let fileIcon = NSWorkspace.shared.icon(forFile: appURL.path)
            let thumbnail = createThumbnail(from: fileIcon, targetSize: targetSize)
            cache.setObject(thumbnail, forKey: cacheKey)
            return thumbnail
        }
        
        // 3. 记录未命中负缓存，避免后续滚动中频繁调用 LaunchServices
        lock.lock()
        unresolvedBundleIDs.insert(trimmed)
        lock.unlock()
        
        return nil
    }
    
    /// 生成紧凑尺寸的独立位图缩略图，避免在每帧渲染中动态对 512x512/1024x1024 大图下采样
    private func createThumbnail(from sourceImage: NSImage, targetSize: NSSize) -> NSImage {
        guard sourceImage.isValid, sourceImage.size.width > 0, sourceImage.size.height > 0 else {
            return sourceImage
        }
        
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(targetSize.width),
            pixelsHigh: Int(targetSize.height),
            bitsPerSample: AppConstants.UI.iconBitmapBitsPerSample,
            samplesPerPixel: AppConstants.UI.iconBitmapSamplesPerPixel,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
        guard let bitmapRep = rep else { return sourceImage }
        bitmapRep.size = targetSize
        
        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(bitmapImageRep: bitmapRep)
        NSGraphicsContext.current = context
        context?.imageInterpolation = .high
        sourceImage.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: NSRect(origin: .zero, size: sourceImage.size),
            operation: .copy,
            fraction: 1.0
        )
        NSGraphicsContext.restoreGraphicsState()
        
        let thumbnail = NSImage(size: targetSize)
        thumbnail.addRepresentation(bitmapRep)
        return thumbnail
    }
    
    /// 清除内存中的图标缓存与未命中记录
    public func clearCache() {
        lock.lock()
        unresolvedBundleIDs.removeAll()
        lock.unlock()
        cache.removeAllObjects()
    }
}
