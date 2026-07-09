object Form2: TForm2
  Left = 0
  Top = 0
  Caption = 'RFID Connector'
  ClientHeight = 518
  ClientWidth = 671
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  OldCreateOrder = False
  Visible = True
  OnCreate = FormCreate
  PixelsPerInch = 96
  TextHeight = 13
  object btn_connect: TButton
    Left = 16
    Top = 8
    Width = 75
    Height = 25
    Caption = 'Verbinden'
    TabOrder = 0
    OnClick = btn_connectClick
  end
  object btn_sendTagID: TButton
    Left = 215
    Top = 39
    Width = 75
    Height = 25
    Caption = 'Senden'
    TabOrder = 1
    OnClick = btn_sendTagIDClick
  end
  object btn_startauto: TButton
    Left = 254
    Top = 8
    Width = 75
    Height = 25
    Caption = 'Start AUTO'
    TabOrder = 2
    OnClick = btn_startautoClick
  end
  object btn_stopauto: TButton
    Left = 340
    Top = 8
    Width = 75
    Height = 25
    Caption = 'Stop AUTO'
    TabOrder = 3
    OnClick = btn_stopautoClick
  end
  object memo_log: TMemo
    Left = 296
    Top = 70
    Width = 372
    Height = 446
    TabOrder = 4
  end
  object edit_sendTagID: TEdit
    Left = 16
    Top = 41
    Width = 193
    Height = 21
    TabOrder = 5
  end
  object Btn_test: TButton
    Left = 421
    Top = 8
    Width = 75
    Height = 25
    Caption = 'Test'
    TabOrder = 6
    OnClick = Btn_testClick
  end
  object btn_versionTest: TButton
    Left = 502
    Top = 8
    Width = 75
    Height = 25
    Caption = 'Version'
    TabOrder = 7
    OnClick = btn_versionTestClick
  end
  object cb_hid: TCheckBox
    Left = 112
    Top = 13
    Width = 97
    Height = 17
    Caption = 'HID'
    TabOrder = 8
    OnClick = cb_hidClick
  end
  object Memo_tag: TMemo
    Left = 16
    Top = 70
    Width = 274
    Height = 446
    TabOrder = 9
  end
  object Edit1: TEdit
    Left = 296
    Top = 41
    Width = 281
    Height = 21
    TabOrder = 10
  end
  object btn_sendCommand: TButton
    Left = 593
    Top = 37
    Width = 75
    Height = 25
    Caption = 'Senden'
    TabOrder = 11
    OnClick = btn_sendTagIDClick
  end
  object btn_taglesen: TButton
    Left = 173
    Top = 8
    Width = 75
    Height = 25
    Caption = 'Tag lesen'
    TabOrder = 12
    OnClick = btn_taglesenClick
  end
  object Timer1: TTimer
    OnTimer = Timer1Timer
    Left = 312
    Top = 264
  end
end
