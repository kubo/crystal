require "c/winnt"

lib LibC
  fun CreatePipe(
    hReadPipe : HANDLE*,
    hWritePipe : HANDLE*,
    lpPipeAttributes : SECURITY_ATTRIBUTES*,
    nSize : DWORD
  ) : BOOL
end
