import Foundation

struct ExportSettings: Sendable {
    var exportAss: Bool
    var exportSrt: Bool
    var exportVtt: Bool
    var exportDocx: Bool
    var srtFullWithRoles: Bool
    var srtSeparateFiles: Bool
    var srtSeparateWithRoles: Bool
    var selectedRoles: Set<String>
    /// цвет маркера каждой роли: тот же, что в окне, поэтому лист и документ совпадают
    var roleHighlights: [String: WordHighlightColor]

    /// те же настройки для другого файла очереди: отметки и цвета принадлежат показанному файлу,
    /// а у соседней серии роли свои. поля перечислять не нужно: меняются ровно два
    func forOtherFile(roles: Set<String>, highlights: [String: WordHighlightColor]) -> ExportSettings {
        var copy: ExportSettings = self
        copy.selectedRoles = roles
        copy.roleHighlights = highlights
        return copy
    }
}
