import Foundation

/// 输入法管理器抽象协议，用于生产环境 Carbon 实现与测试环境 Mock 解耦
public protocol InputSourceManagerProtocol: AnyObject, Sendable {
    /// 获取当前系统处于活跃状态的输入法
    var currentSource: InputSourceModel { get }
    
    /// 获取系统已安装并启用的所有可用键盘输入法
    var availableSources: [InputSourceModel] { get }
    
    /// 获取当前系统中最匹配的可用 ASCII/英文输入法 ID
    var defaultAsciiSourceID: String { get }
    
    /// 切换系统输入法到指定 Source ID
    /// - Parameter sourceID: 目标输入法 ID
    /// - Returns: 切换是否发起成功
    @discardableResult
    func selectSource(id sourceID: String) -> Bool
    
    /// 注册用户手动切换输入法的回调通知
    /// - Parameter handler: 当用户主动通过按键或菜单切换输入法时触发
    func setOnUserChangedSourceHandler(_ handler: (@Sendable (InputSourceModel) -> Void)?)
    
    /// 重新刷新可用输入法列表缓存
    func reloadAvailableSources()
}
