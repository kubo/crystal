require "c/winnt"

# WSAOVERLAPPED is the primary communication structure for async I/O on Windows.
# See https://docs.microsoft.com/en-us/windows/win32/api/winsock2/ns-winsock2-wsaoverlapped
@[Extern]
struct WSAOVERLAPPED
  property internal : LibC::ULONG_PTR
  property internalHigh : LibC::ULONG_PTR
  offset : LibC::DWORD
  offsetHigh : LibC::DWORD
  hEvent : LibC::HANDLE
  property cEvent : Void*

  def initialize(fiber : Fiber)
    @internal = 0
    @internalHigh = 0
    @cEvent = fiber.unsafe_as(Pointer(Void))
  end
end

@[Link("advapi32")]
lib LibC
  struct OVERLAPPED_ENTRY
    lpCompletionKey : ULONG_PTR
    lpOverlapped : WSAOVERLAPPED*
    internal : ULONG_PTR
    dwNumberOfBytesTransferred : DWORD
  end

  fun WSAGetLastError : Int

  fun CreateIoCompletionPort(
    fileHandle : HANDLE,
    existingCompletionPort : HANDLE,
    completionKey : ULONG_PTR,
    numberOfConcurrentThreads : DWORD
  ) : HANDLE

  fun GetQueuedCompletionStatus(
    completionPort : HANDLE,
    lpNumberOfBytesTransferred : DWORD*,
    lpCompletionKey : ULONG_PTR*,
    lpOverlapped : WSAOVERLAPPED*,
    dwMilliseconds : DWORD
  ) : BOOL

  fun GetQueuedCompletionStatusEx(
    completionPort : HANDLE,
    lpCompletionPortEntries : OVERLAPPED_ENTRY*,
    ulCount : ULong,
    ulNumEntriesRemoved : ULong*,
    dwMilliseconds : DWORD,
    fAlertable : BOOL
  ) : BOOL

  fun PostQueuedCompletionStatus(
    completionPort : HANDLE,
    dwNumberOfBytesTransferred : DWORD,
    dwCompletionKey : ULONG_PTR,
    lpOverlapped : WSAOVERLAPPED*
  ) : BOOL
end
