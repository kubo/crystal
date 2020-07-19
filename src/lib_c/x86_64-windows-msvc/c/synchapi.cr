require "c/basetsd"
require "c/int_safe"

lib LibC
  fun Sleep(dwMilliseconds : DWORD)
  fun WaitForSingleObject(hHandle : HANDLE, dwMilliseconds : DWORD) : DWORD
  fun CreateEventW(lpEventAttributes : SECURITY_ATTRIBUTES*, bManualReset : BOOL,
                   bInitialState : BOOL, lpName : LPWSTR) : HANDLE
end
