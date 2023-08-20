import Combine
import Foundation

final class LineMover {
    private struct MoveLinesOperation {
        let removeRange: NSRange
        let replacementRange: NSRange
        let replacementString: String
        let selectedRange: NSRange
    }

    private let stringView: CurrentValueSubject<StringView, Never>
    private let lineManager: CurrentValueSubject<LineManager, Never>
    private let selectedRange: CurrentValueSubject<NSRange, Never>
    private let lineEndings: CurrentValueSubject<LineEnding, Never>
    private let textEditor: TextEditor
    private let undoManager: UndoManager

    init(
        stringView: CurrentValueSubject<StringView, Never>,
        lineManager: CurrentValueSubject<LineManager, Never>,
        selectedRange: CurrentValueSubject<NSRange, Never>,
        lineEndings: CurrentValueSubject<LineEnding, Never>,
        textEditor: TextEditor,
        undoManager: UndoManager
    ) {
        self.stringView = stringView
        self.lineManager = lineManager
        self.selectedRange = selectedRange
        self.lineEndings = lineEndings
        self.textEditor = textEditor
        self.undoManager = undoManager
    }

    func moveSelectedLinesUp() {
        moveSelectedLine(byOffset: -1, undoActionName: L10n.Undo.ActionName.moveLinesUp)
    }

    func moveSelectedLinesDown() {
        moveSelectedLine(byOffset: 1, undoActionName: L10n.Undo.ActionName.moveLinesDown)
    }
}

private extension LineMover {
    private func moveSelectedLine(byOffset lineOffset: Int, undoActionName: String) {
        guard let operation = operationForMovingLines(in: selectedRange.value, byOffset: lineOffset) else {
            return
        }
        undoManager.endUndoGrouping()
        undoManager.beginUndoGrouping()
        textEditor.replaceText(in: operation.removeRange, with: "")
        textEditor.replaceText(in: operation.replacementRange, with: operation.replacementString)
//        #if os(iOS)
//        textView.notifyInputDelegateAboutSelectionChangeInLayoutSubviews = true
//        #endif
        selectedRange.value = operation.selectedRange
        undoManager.endUndoGrouping()
    }

    private func operationForMovingLines(in selectedRange: NSRange, byOffset lineOffset: Int) -> MoveLinesOperation? {
        // This implementation of moving lines is naive, as it first removes the selected lines and then inserts the text at the target line.
        // That requires two parses of the syntax tree and two operations on our line manager. Ideally we would do this in one operation.
        let isMovingDown = lineOffset > 0
        let selectedLines = lineManager.value.lines(in: selectedRange)
        guard !selectedLines.isEmpty else {
            return nil
        }
        let firstLine = selectedLines[0]
        let lastLine = selectedLines[selectedLines.count - 1]
        let firstLineIndex = firstLine.index
        var targetLineIndex = firstLineIndex + lineOffset
        if isMovingDown {
            targetLineIndex += selectedLines.count - 1
        }
        guard targetLineIndex >= 0 && targetLineIndex < lineManager.value.lineCount else {
            return nil
        }
        // Find the line to move the selected text to.
        let targetLine = lineManager.value.line(atRow: targetLineIndex)
        // Find the range of text to remove. That's the range encapsulating selected lines.
        let removeLocation = firstLine.location
        let removeLength = lastLine.location + lastLine.data.totalLength - removeLocation
        // Find the location to insert the text at.
        var insertLocation = targetLine.location
        if isMovingDown {
            insertLocation += targetLine.data.totalLength - removeLength
        }
        // Update the selected range to match the old one but at the new lines.
        var locationOffset = insertLocation - removeLocation
        // Perform the remove and insert operations.
        var removeRange = NSRange(location: removeLocation, length: removeLength)
        let insertRange = NSRange(location: insertLocation, length: 0)
        var text = stringView.value.substring(in: removeRange) ?? ""
        if isMovingDown && targetLine.data.delimiterLength == 0 {
            if lastLine.data.delimiterLength > 0 {
                // We're moving to a line with no line break so we'll remove the last line break from the text we're moving.
                // This behavior matches the one of Nova.
                text.removeLast(lastLine.data.delimiterLength)
            }
            // Since the line we're moving to has no line break, we should add one in the beginning of the text.
            text = lineEndings.value.symbol + text
            locationOffset += lineEndings.value.symbol.utf16.count
        } else if !isMovingDown && lastLine.data.delimiterLength == 0 {
            // The last line we're moving has no line break, so we'll add one.
            text += lineEndings.value.symbol
            // Adjust the removal range to remove the line break of the line we're moving to.
            if targetLine.data.delimiterLength > 0 {
                removeRange.location -= targetLine.data.delimiterLength
                removeRange.length += targetLine.data.delimiterLength
            }
        }
        let newSelectedRange = NSRange(location: selectedRange.location + locationOffset, length: selectedRange.length)
        return MoveLinesOperation(
            removeRange: removeRange,
            replacementRange: insertRange,
            replacementString: text,
            selectedRange: newSelectedRange
        )
    }
}