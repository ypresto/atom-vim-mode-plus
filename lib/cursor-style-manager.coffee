{Disposable, CompositeDisposable} = require 'atom'

settings = require './settings'
swrap = require './selection-wrapper'

lineHeight = null

getDomNode = (editorElement, cursor) ->
  cursorsComponent = editorElement.component.linesComponent.cursorsComponent
  cursorsComponent.cursorNodesById[cursor.id]

# Return cursor style offset(top, left)
# ---------------------------------------
getOffset = (submode, selection) ->
  {top, left} = {}
  {cursor, editor} = selection
  switch submode
    when 'characterwise', 'blockwise'
      unless selection.isReversed()
        if cursor.isAtBeginningOfLine()
          top = -lineHeight
        else
          left = -1
    when 'linewise'
      bufferPoint = swrap(selection).getCharacterwiseHeadPosition()
      if editor.isSoftWrapped()
        screenPoint = editor.screenPositionForBufferPosition(bufferPoint)
        bufferRange = editor.bufferRangeForBufferRow(bufferPoint.row)
        screenRows = editor.screenRangeForBufferRange(bufferRange).getRows()
        rows = if selection.isReversed()
          screenRows.indexOf(screenPoint.row)
        else
          -(screenRows.reverse().indexOf(screenPoint.row) + 1)
        top = rows * lineHeight
        left = screenPoint.column
      else
        # In linwise selection, cursor isAtBeginningOfLine of next row of selected row.
        # But there is one exception.
        # When very last line is not end with newline("\n").
        # select linewise by `V` put cursor at last char(=end of line).
        # In this case, we minus(-) cursor's column to reset offset to column 0.
        # But when `V` selection.isReversed() cursor is at column 0, so we don't have to reset offset.
        left = 0
        unless selection.isReversed()
          if cursor.isAtBeginningOfLine()
            top = -lineHeight
          else
            # This is very special case when very last line is not end with newline("\n")
            left -= cursor.getBufferColumn()
        left += bufferPoint.column
  {top, left}

setStyleOffset = (cursor, {submode, editorElement}) ->
  domNode = getDomNode(editorElement, cursor)
  # This guard is for test spec, not all spec have dom attached.
  return (new Disposable) unless domNode

  {style} = domNode
  {left, top} = getOffset(submode, cursor.selection)
  style.setProperty('top', "#{top}em") if top?
  style.setProperty('left', "#{left}ch") if left?

  new Disposable ->
    style.removeProperty('top')
    style.removeProperty('left')

# Display cursor in visual mode.
# ----------------------------------
class CursorStyleManager
  constructor: (@vimState) ->
    {@editorElement, @editor} = @vimState
    @lineHeightObserver = atom.config.observe 'editor.lineHeight', (newValue) =>
      lineHeight = newValue
      @refresh()

  destroy: ->
    @subscriptions.dispose()
    @lineHeightObserver.dispose()
    {@subscriptions, @lineHeightObserver} = {}

  refresh: ->
    {submode} = @vimState
    @subscriptions?.dispose()
    @subscriptions = new CompositeDisposable
    return unless (@vimState.isMode('visual') and settings.get('showCursorInVisualMode'))

    cursors = cursorsToShow = @editor.getCursors()
    if submode is 'blockwise'
      cursorsToShow = @vimState.blockwiseSelections.map (bs) -> bs.getHead().cursor

    for cursor in cursors
      if cursor in cursorsToShow
        cursor.setVisible(true) unless cursor.isVisible()
      else
        cursor.setVisible(false) if cursor.isVisible()

    # [NOTE] In BlockwiseSelect we add selections(and corresponding cursors) in bluk.
    # But corresponding cursorsComponent(HTML element) is added in sync.
    # So to modify style of cursorsComponent, we have to make sure corresponding cursorsComponent
    # is available by component in sync to model.
    @editorElement.component.updateSync()

    for cursor in cursorsToShow
      @subscriptions.add setStyleOffset(cursor, {submode, @editorElement})

module.exports = CursorStyleManager
