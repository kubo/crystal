lib LibC
  fun GetOverlappedResult(hFile : HANDLE, lpOverlapped : OVERLAPPED*,
                          lpNumberOfBytesTransferred : DWORD*, bWait : BOOL) : BOOL
end
