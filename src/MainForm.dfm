object frmMain: TfrmMain
  Left = 0
  Top = 0
  Caption = 'SoundsBrowse'
  ClientHeight = 720
  ClientWidth = 1200
  Color = clBtnFace
  Constraints.MinHeight = 400
  Constraints.MinWidth = 700
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  KeyPreview = True
  Menu = mnuMain
  Position = poScreenCenter
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  OnKeyDown = FormKeyDown
  OnKeyPress = FormKeyPress
  OnMouseWheel = FormMouseWheel
  TextHeight = 15
  object pnlTree: TPanel
    Left = 0
    Top = 0
    Width = 300
    Height = 697
    Align = alLeft
    BevelOuter = bvNone
    TabOrder = 0
  end
  object splTree: TSplitter
    Left = 300
    Top = 0
    Width = 5
    Height = 697
    MinSize = 120
  end
  object pnlRight: TPanel
    Left = 305
    Top = 0
    Width = 895
    Height = 697
    Align = alClient
    BevelOuter = bvNone
    TabOrder = 1
    object pnlFiles: TPanel
      Left = 0
      Top = 0
      Width = 895
      Height = 452
      Align = alClient
      BevelOuter = bvNone
      TabOrder = 0
      object pnlFilter: TPanel
        Left = 0
        Top = 0
        Width = 895
        Height = 34
        Align = alTop
        BevelOuter = bvNone
        TabOrder = 0
        DesignSize = (
          895
          34)
        object edtFilter: TEdit
          Left = 6
          Top = 5
          Width = 883
          Height = 23
          Anchors = [akLeft, akTop, akRight]
          TabOrder = 0
          TextHint = 'Filter  (Ctrl+F, Esc clears; several words = all must match)'
          OnChange = edtFilterChange
          OnKeyDown = edtFilterKeyDown
        end
      end
      object lvFiles: TListView
        Left = 0
        Top = 34
        Width = 895
        Height = 418
        Align = alClient
        BorderStyle = bsNone
        Columns = <
          item
            Caption = 'Name'
            Width = 380
          end
          item
            Alignment = taRightJustify
            Caption = 'Length'
            Width = 70
          end
          item
            Alignment = taRightJustify
            Caption = 'Rate'
            Width = 60
          end
          item
            Alignment = taRightJustify
            Caption = 'Bits'
            Width = 45
          end
          item
            Alignment = taRightJustify
            Caption = 'Ch'
            Width = 40
          end
          item
            Caption = 'Type'
            Width = 55
          end
          item
            Alignment = taRightJustify
            Caption = 'Size'
            Width = 80
          end>
        DoubleBuffered = True
        HideSelection = False
        MultiSelect = True
        OwnerData = True
        ReadOnly = True
        RowSelect = True
        ParentDoubleBuffered = False
        TabOrder = 1
        ViewStyle = vsReport
        OnClick = lvFilesClick
        OnColumnClick = lvFilesColumnClick
        OnData = lvFilesData
        OnDblClick = lvFilesDblClick
        OnSelectItem = lvFilesSelectItem
      end
    end
    object splWave: TSplitter
      Left = 0
      Top = 452
      Width = 895
      Height = 5
      Cursor = crVSplit
      Align = alBottom
      MinSize = 100
    end
    object pnlWave: TPanel
      Left = 0
      Top = 457
      Width = 895
      Height = 240
      Align = alBottom
      BevelOuter = bvNone
      TabOrder = 1
      object pnlTransport: TPanel
        Left = 0
        Top = 200
        Width = 895
        Height = 40
        Align = alBottom
        BevelOuter = bvNone
        DoubleBuffered = True
        ParentBackground = False
        ParentDoubleBuffered = False
        TabOrder = 0
        DesignSize = (
          895
          40)
        object lblTime: TLabel
          Left = 330
          Top = 12
          Width = 150
          Height = 15
          Caption = '0:00.000 / 0:00.000'
          Font.Charset = DEFAULT_CHARSET
          Font.Color = clWindowText
          Font.Height = -12
          Font.Name = 'Consolas'
          Font.Style = []
          ParentFont = False
        end
        object lblVolume: TLabel
          Left = 676
          Top = 12
          Width = 41
          Height = 15
          Anchors = [akTop, akRight]
          Caption = 'Volume'
        end
        object btnPlay: TButton
          Left = 8
          Top = 6
          Width = 75
          Height = 28
          Caption = 'Play'
          ParentDoubleBuffered = False
          TabOrder = 0
          TabStop = False
          OnClick = btnPlayClick
        end
        object btnStop: TButton
          Left = 88
          Top = 6
          Width = 75
          Height = 28
          Caption = 'Stop'
          ParentDoubleBuffered = False
          TabOrder = 1
          TabStop = False
          OnClick = btnStopClick
        end
        object chkLoop: TCheckBox
          Left = 178
          Top = 11
          Width = 60
          Height = 17
          Caption = 'Loop'
          ParentDoubleBuffered = False
          TabOrder = 2
          TabStop = False
          OnClick = chkLoopClick
        end
        object chkAutoPlay: TCheckBox
          Left = 240
          Top = 11
          Width = 80
          Height = 17
          Caption = 'Auto-play'
          Checked = True
          State = cbChecked
          ParentDoubleBuffered = False
          TabOrder = 3
          TabStop = False
        end
        object tbVolume: TTrackBar
          Left = 724
          Top = 8
          Width = 165
          Height = 26
          Anchors = [akTop, akRight]
          Max = 100
          Position = 80
          ShowSelRange = False
          ParentDoubleBuffered = False
          TabOrder = 4
          TabStop = False
          TickStyle = tsNone
          OnChange = tbVolumeChange
        end
      end
    end
  end
  object sbMain: TStatusBar
    Left = 0
    Top = 697
    Width = 1200
    Height = 23
    Panels = <
      item
        Width = 450
      end
      item
        Width = 180
      end
      item
        Width = 320
      end
      item
        Width = 50
      end>
  end
  object tmrPosition: TTimer
    Interval = 30
    OnTimer = tmrPositionTimer
    Left = 40
    Top = 48
  end
  object tmrSelect: TTimer
    Enabled = False
    Interval = 60
    OnTimer = tmrSelectTimer
    Left = 112
    Top = 48
  end
  object mnuMain: TMainMenu
    Left = 184
    Top = 48
    object mnuFile: TMenuItem
      Caption = '&File'
      object mnuFileExit: TMenuItem
        Caption = 'E&xit'
        OnClick = mnuFileExitClick
      end
    end
    object mnuOptions: TMenuItem
      Caption = '&Options'
      OnClick = mnuOptionsClick
      object mnuExplorerMenu: TMenuItem
        Caption = '&Show in Explorer context menu'
        OnClick = mnuExplorerMenuClick
      end
      object mnuOptionsSep1: TMenuItem
        Caption = '-'
      end
      object mnuSoundFont: TMenuItem
        Caption = 'Choose MIDI sound&font...'
        OnClick = mnuSoundFontClick
      end
      object mnuSoundFontBundled: TMenuItem
        Caption = 'Use &bundled MIDI soundfont'
        OnClick = mnuSoundFontBundledClick
      end
    end
  end
end
