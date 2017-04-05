unit _fmMain;

interface

uses
  PeerClient, ValueList, ThreadUtils,
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls;

type
  TfmMain = class(TForm)
    Panel1: TPanel;
    edIP: TEdit;
    edRoomID: TEdit;
    edUserID: TEdit;
    btConnect: TButton;
    btDisconnect: TButton;
    moMsg: TMemo;
    edMsg: TEdit;
    btLogin: TButton;
    tmClock: TTimer;
    btStart: TButton;
    btStop: TButton;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure btConnectClick(Sender: TObject);
    procedure edMsgKeyPress(Sender: TObject; var Key: Char);
    procedure btDisconnectClick(Sender: TObject);
    procedure btLoginClick(Sender: TObject);
    procedure tmClockTimer(Sender: TObject);
    procedure btStartClick(Sender: TObject);
    procedure btStopClick(Sender: TObject);
  private
    FCountSend : DWord;
    FCountRecv : DWord;
  private
    FPeerClient : TPeerClient;
    procedure on_FPeerClient_Connected(ASender:TObject);
    procedure on_FPeerClient_Disconnected(ASender:TObject);
    procedure on_FPeerClient_Text(Sender:TObject; const AText:string);
    procedure on_FPeerClient_Data(Sender:TObject; AData:pointer; ASize:integer);
  public
  end;

var
  fmMain: TfmMain;

implementation

{$R *.dfm}

procedure TfmMain.btConnectClick(Sender: TObject);
begin
  if FPeerClient.Connect(edIP.Text) = false then begin
    MessageDlg('서버에 접속 할 수가 없습니다.', mtError, [mbOK], 0);
    Exit;
  end;
end;

procedure TfmMain.btDisconnectClick(Sender: TObject);
begin
  FPeerClient.Disconnect;
end;

procedure TfmMain.btLoginClick(Sender: TObject);
begin
  FPeerClient.sp_Login(edRoomID.Text, edUserID.Text);
end;

procedure TfmMain.btStartClick(Sender: TObject);
begin
  tmClock.Enabled := true;
end;

procedure TfmMain.btStopClick(Sender: TObject);
begin
  tmClock.Enabled := false;
end;

procedure TfmMain.edMsgKeyPress(Sender: TObject; var Key: Char);
begin
  if Key = #13 then begin
    Key := #0;
    FPeerClient.SendToAll(edMsg.Text);
    edMsg.Clear;
  end;
end;

procedure TfmMain.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  FPeerClient.Disconnect;
end;

procedure TfmMain.FormCreate(Sender: TObject);
begin
  SetPriorityClass( GetCurrentProcess, REALTIME_PRIORITY_CLASS );
  SetThreadPriorityFast;

  FCountSend := 0;
  FCountRecv := 0;

  FPeerClient := TPeerClient.Create;
  FPeerClient.OnConnected := on_FPeerClient_Connected;
  FPeerClient.OnDisconnected := on_FPeerClient_Disconnected;
  FPeerClient.OnText := on_FPeerClient_Text;
  FPeerClient.OnData := on_FPeerClient_Data;
end;

procedure TfmMain.FormDestroy(Sender: TObject);
begin
  FreeAndNil(FPeerClient);
end;

procedure TfmMain.on_FPeerClient_Connected(ASender: TObject);
begin
  moMsg.Lines.Add('Connected!')
end;

procedure TfmMain.on_FPeerClient_Data(Sender: TObject; AData: pointer;
  ASize: integer);
var
  Count : DWord;
begin
  Move(AData^, Count, ASize);

  if (Count - FCountRecv) <> 1 then
    moMsg.Lines.Add( Format('Count: %d, FCountRecv: %d', [Count, FCountRecv]) );

  FCountRecv := Count;
end;

procedure TfmMain.on_FPeerClient_Disconnected(ASender: TObject);
begin
  moMsg.Lines.Add('Disconnected!!!')
end;

procedure TfmMain.on_FPeerClient_Text(Sender: TObject; const AText: string);
begin
  moMsg.Lines.Add(AText);
end;

procedure TfmMain.tmClockTimer(Sender: TObject);
begin
  Inc(FCountSend);
  FPeerClient.SendToAll(@FCountSend, SizeOf(FCountSend));
end;

end.
