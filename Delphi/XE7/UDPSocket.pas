unit UDPSocket;

interface

uses
  WinSock, SimpleThread,
  Windows, Classes, SysUtils, SyncObjs;

type
  TUDPReceivedEvent = procedure(const APeerIP:string; APeerPort:integer; AData:pointer; ASize:integer) of object;

  TUDPSocket = class(TComponent)
  private
    FCS : TCriticalSection;
    FSocket : TSocket;
    FBuffer : Pointer;
    function do_Bind:boolean;
  private
    FSimpleThread : TSimpleThread;
    procedure on_FSimpleThread_Execute(ASimpleThread:TSimpleThread);
  private
    FBufferSize : integer;
    FPort: integer;
    FActive: boolean;
    FOnReceived: TUDPReceivedEvent;
    FTimeOutRead: integer;
    FTimeOutWrite: integer;
    FIsServer: boolean;
    procedure SetPort(const Value: integer);
    procedure SetBufferSize(const Value: integer);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    procedure Start(ANeedBinding:boolean=true);
    procedure Stop;

    procedure SendTo(const AHost:string; APort:integer; AData:pointer; ASize:integer); overload;
    procedure SendTo(const AHost:string; APort:integer; AText:string); overload;
  published
    property Active : boolean read FActive;
    property Port : integer read FPort write SetPort;
    property IsServer : boolean read FIsServer;
    property BufferSize : integer read FBufferSize write SetBufferSize;
    property TimeOutRead : integer read FTimeOutRead write FTimeOutRead;
    property TimeOutWrite : integer read FTimeOutWrite write FTimeOutWrite;
    property OnReceived : TUDPReceivedEvent read FOnReceived write FOnReceived;
  end;

var
  WSAData : TWSAData;

implementation

{ TUDPSocket }

constructor TUDPSocket.Create(AOwner: TComponent);
begin
  inherited;

  FSocket := -1;
  FActive := false;
  FIsServer := false;
  FBufferSize := 1024 * 1024;
  FTimeOutRead := 5;
  FTimeOutWrite := 5;

  GetMem(FBuffer, FBufferSize);

  FCS := TCriticalSection.Create;

  FSimpleThread := TSimpleThread.Create('TUDPSocket', on_FSimpleThread_Execute);
end;

destructor TUDPSocket.Destroy;
begin
  Stop;

  FSimpleThread.TerminateNow;

//  FreeAndNil(FSimpleThread);

  inherited;
end;

function TUDPSocket.do_Bind: boolean;
var
  SockAddr : TSockAddr;
begin
  FillChar(SockAddr, SizeOf(TSockAddr), 0);
  SockAddr.sin_family := AF_INET;
  SockAddr.sin_port := htons(FPort);
  SockAddr.sin_addr.s_addr := htonl(INADDR_ANY);

  Result := bind(FSocket, SockAddr, sizeof(SockAddr)) > -1;
end;

procedure TUDPSocket.on_FSimpleThread_Execute(ASimpleThread: TSimpleThread);
var
  iBytes, iSizeOfAddr : integer;
  SockAddr : TSockAddr;
  Data : pointer;
  ReceivedEvent : TUDPReceivedEvent;
begin
  while ASimpleThread.Terminated = false do begin
    if (FSocket = -1) or (FIsServer = false) then begin
      ASimpleThread.Sleep(5);
      Continue;
    end;

    try
      iSizeOfAddr := SizeOf(SockAddr);
      iBytes := recvfrom(FSocket, FBuffer^, FBufferSize, 0, SockAddr, iSizeOfAddr);

      if iBytes <= 0 then Continue;

      ReceivedEvent := FOnReceived;

      GetMem(Data, iBytes);
      try
        Move(FBuffer^, Data^, iBytes);
        if Assigned(ReceivedEvent) then
          ReceivedEvent(String(inet_ntoa(SockAddr.sin_addr)), ntohs(SockAddr.sin_port), Data, iBytes);
      finally
        FreeMem(Data);
      end;
    except
      ASimpleThread.Sleep(5);
    end;
  end;

  FreeMem(FBuffer);
  FreeAndNil(FCS);
end;

procedure TUDPSocket.SendTo(const AHost: string; APort: integer; AText: string);
var
  ssData : TStringStream;
begin
  ssData := TStringStream.Create;
  try
    ssData.WriteString(AText);
    SendTo(AHost, APort, ssData.Memory, ssData.Size);
  finally
    ssData.Free;
  end;
end;

procedure TUDPSocket.SendTo(const AHost: string; APort: integer; AData: pointer;
  ASize: integer);
var
  Host : AnsiString;
  SockAddr : TSockAddr;
begin
  Host := AnsiString(AHost);

  FillChar(SockAddr, SizeOf(SockAddr), 0);
  SockAddr.sin_family := AF_INET;
  SockAddr.sin_port := htons(APort);
  SockAddr.sin_addr.S_addr := inet_addr(PAnsiChar(Host));

  FCS.Enter;
  try
    if FSocket = -1 then Exit;

    WinSock.SendTo(FSocket, AData^, ASize, 0, SockAddr, SizeOf(TSockAddr));
  finally
    FCS.Leave;
  end;
end;

procedure TUDPSocket.SetBufferSize(const Value: integer);
begin
  FCS.Acquire;
  try
    if FSocket <> -1 then
      raise Exception.Create('Socket has opened.  Close it before you change this property.');

    FBufferSize := Value;

    FreeMem(FBuffer);
    GetMem(FBuffer, Value);
  finally
    FCS.Release;
  end;
end;

procedure TUDPSocket.SetPort(const Value: integer);
begin
  FCS.Acquire;
  try
    if FSocket <> -1 then
      raise Exception.Create('Socket has opened.  Close it before you change this property.');

    FPort := Value;
  finally
    FCS.Release;
  end;
end;

procedure TUDPSocket.Start(ANeedBinding:boolean);
var
  iBufferSize : integer;
  iTimeOutRead, iTimeOutWrite : Integer;
begin
  Stop;

  FCS.Acquire;
  try
    FIsServer := ANeedBinding;

    FSocket := socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if FSocket = -1 then
      raise Exception.Create('Can''t open Socket');

    iBufferSize := FBufferSize;
    setsockopt(FSocket, SOL_SOCKET, SO_SNDBUF, @iBufferSize, SizeOf(iBufferSize));
    setsockopt(FSocket, SOL_SOCKET, SO_RCVBUF, @iBufferSize, SizeOf(iBufferSize));

    iTimeOutRead := FTimeOutRead;
    setsockopt(FSocket, SOL_SOCKET, SO_RCVTIMEO, @iTimeOutRead, SizeOf(iTimeOutRead));

    iTimeOutWrite := FTimeOutWrite;
    setsockopt(FSocket, SOL_SOCKET, SO_SNDTIMEO, @iTimeOutWrite, SizeOf(iTimeOutWrite));

    if ANeedBinding then begin
      if FPort = 0 then begin
        FPort := $FFFF;
        while (FActive = false) and (FPort > 0) do begin
          FPort := FPort - 1;
          FActive := do_Bind;
        end;
      end else begin
        FActive := do_Bind;
      end;

      if not FActive then
        raise Exception.Create('The port is already using.');
    end;
  finally
    FCS.Release;
  end;
end;

procedure TUDPSocket.Stop;
begin
  FActive := false;
  FIsServer := false;

  FCS.Acquire;
  try
    if FSocket <> -1 then begin
      closesocket(FSocket);
      FSocket := -1;
    end;
  finally
    FCS.Release;
  end;
end;

initialization
  if WSAStartup($0202, WSAData) <> 0 then
    raise Exception.Create(SysErrorMessage(GetLastError));
finalization
  WSACleanup;
end.
