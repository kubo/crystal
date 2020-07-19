require "c/winnt"
require "c/basetsd"

lib LibC
  fun GetFullPathNameW(lpFileName : LPWSTR, nBufferLength : DWORD, lpBuffer : LPWSTR, lpFilePart : LPWSTR*) : DWORD
  fun GetTempPathW(nBufferLength : DWORD, lpBuffer : LPWSTR) : DWORD

  FILE_TYPE_CHAR    = DWORD.new(0x2)
  FILE_TYPE_DISK    = DWORD.new(0x1)
  FILE_TYPE_PIPE    = DWORD.new(0x3)
  FILE_TYPE_UNKNOWN = DWORD.new(0x0)

  fun GetFileType(hFile : HANDLE) : DWORD

  struct BY_HANDLE_FILE_INFORMATION
    dwFileAttributes : DWORD
    ftCreationTime : FILETIME
    ftLastAccessTime : FILETIME
    ftLastWriteTime : FILETIME
    dwVolumeSerialNumber : DWORD
    nFileSizeHigh : DWORD
    nFileSizeLow : DWORD
    nNumberOfLinks : DWORD
    nFileIndexHigh : DWORD
    nFileIndexLow : DWORD
  end

  fun GetFileInformationByHandle(hFile : HANDLE, lpFileInformation : BY_HANDLE_FILE_INFORMATION*) : BOOL
  fun GetFileAttributesW(lpFileName : LPWSTR) : DWORD
  fun SetFileAttributesW(lpFileName : LPWSTR, dwFileAttributes : DWORD) : BOOL
  fun GetFileAttributesExW(lpFileName : LPWSTR, fInfoLevelId : GET_FILEEX_INFO_LEVELS, lpFileInformation : Void*) : BOOL

  CREATE_NEW    = 1
  CREATE_ALWAYS = 2
  OPEN_EXISTING = 3
  OPEN_ALWAYS   = 4

  FILE_ATTRIBUTE_NORMAL      =       0x80
  FILE_FLAG_OVERLAPPED       = 0x40000000
  FILE_FLAG_BACKUP_SEMANTICS = 0x02000000

  FILE_SHARE_READ   = 0x1
  FILE_SHARE_WRITE  = 0x2
  FILE_SHARE_DELETE = 0x4

  fun CreateFileW(lpFileName : LPWSTR, dwDesiredAccess : DWORD, dwShareMode : DWORD,
                  lpSecurityAttributes : SECURITY_ATTRIBUTES*, dwCreationDisposition : DWORD,
                  dwFlagsAndAttributes : DWORD, hTemplateFile : HANDLE) : HANDLE

  struct OVERLAPPED_OFFSET
    offset : DWORD
    offsetHigh : DWORD
  end

  union OVERLAPPED_UNION
    offset : OVERLAPPED_OFFSET
    pointer : Void*
  end

  struct OVERLAPPED
    internal : ULONG_PTR
    internalHigh : ULONG_PTR
    union : OVERLAPPED_UNION
    hEvent : HANDLE
  end

  fun ReadFile(hFile : HANDLE, lpBuffer : Void*, nNumberOfBytesToRead : DWORD, lpNumberOfBytesRead : DWORD*, lpOverlapped : OVERLAPPED*) : BOOL

  MAX_PATH = 260

  struct WIN32_FIND_DATAW
    dwFileAttributes : DWORD
    ftCreationTime : FILETIME
    ftLastAccessTime : FILETIME
    ftLastWriteTime : FILETIME
    nFileSizeHigh : DWORD
    nFileSizeLow : DWORD
    dwReserved0 : DWORD
    dwReserved1 : DWORD
    cFileName : WCHAR[MAX_PATH]
    cAlternateFileName : WCHAR[14]
  end

  fun FindFirstFileW(lpFileName : LPWSTR, lpFindFileData : WIN32_FIND_DATAW*) : HANDLE
  fun FindNextFileW(hFindFile : HANDLE, lpFindFileData : WIN32_FIND_DATAW*) : BOOL
  fun FindClose(hFindFile : HANDLE) : BOOL

  fun SetFileTime(hFile : HANDLE, lpCreationTime : FILETIME*,
                  lpLastAccessTime : FILETIME*, lpLastWriteTime : FILETIME*) : BOOL

  fun FlushFileBuffers(hFile : HANDLE) : BOOL
  fun GetFileSizeEx(hFile : HANDLE, lpFileSize : LARGE_INTEGER*) : BOOL
  fun ReadFile(hFile : HANDLE, lpBuffer : Void*, nNumberOfBytesToRead : DWORD,
               lpNumberOfBytesRead : DWORD*, lpOverlapped : OVERLAPPED*) : BOOL
  fun SetEndOfFile(hFile : HANDLE) : BOOL
  fun SetFilePointerEx(hFile : HANDLE, liDistanceToMove : LARGE_INTEGER,
                       lpNewFilePointer : LARGE_INTEGER*, dwMoveMethod : DWORD) : BOOL
  fun WriteFile(hFile : HANDLE, lpBuffer : Void*, nNumberOfBytesToWrite : DWORD,
                lpNumberOfBytesWritten : DWORD*, lpOverlapped : OVERLAPPED*) : BOOL
end
