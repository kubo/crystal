require "c/io"
require "c/fcntl"
require "c/fileapi"
require "c/ioapiset"
require "c/sys/utime"
require "c/sys/stat"
require "c/winbase"

module Crystal::System::File
  def self.open(filename : String, mode : String, perm : Int32 | ::File::Permissions) : {LibC::HANDLE, Bool, Bool}
    perm = ::File::Permissions.new(perm) if perm.is_a? Int32
    oflag = open_flag(mode)
    overlapped = true
    append = false

    share = LibC::FILE_SHARE_READ | LibC::FILE_SHARE_WRITE | LibC::FILE_SHARE_DELETE

    case oflag & (LibC::O_RDONLY | LibC::O_WRONLY | LibC::O_RDWR)
    when LibC::O_RDONLY
      access = LibC::GENERIC_READ
    when LibC::O_WRONLY
      access = LibC::GENERIC_WRITE
    when LibC::O_RDWR
      access = LibC::GENERIC_READ | LibC::GENERIC_WRITE
    else
      raise ::File::Error.new("Invalid file open mode '#{mode}'", file: filename)
    end

    case oflag & (LibC::O_CREAT | LibC::O_TRUNC)
    when 0
      create = LibC::OPEN_EXISTING
    when LibC::O_CREAT | LibC::O_TRUNC
      create = LibC::CREATE_ALWAYS
    when LibC::O_CREAT
      create = LibC::OPEN_ALWAYS
    else
      raise ::File::Error.new("Invalid file open mode '#{mode}'", file: filename)
    end

    if oflag & LibC::O_APPEND != 0
      append = true
    end

    attr = LibC::FILE_FLAG_OVERLAPPED

    # Only the owner writable bit is used, since windows only supports
    # the read only attribute.
    if perm.owner_write?
      attr |= LibC::FILE_ATTRIBUTE_NORMAL
    else
      attr |= LibC::FILE_ATTRIBUTE_READONLY
    end

    case filename
    when "CONIN$", "CONOUT$", "CON"
      # Consoles
      # See https://docs.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-createfilew#consoles
      overlapped = false # FILE_FLAG_OVERLAPPED is ignoread
      share = LibC::FILE_SHARE_READ | LibC::FILE_SHARE_WRITE
      create = LibC::OPEN_EXISTING
    end

    handle = LibC.CreateFileW(
      to_windows_path(filename),
      access,
      share,
      nil,
      create,
      attr,
      LibC::HANDLE.null
    )
    if handle == LibC::INVALID_HANDLE_VALUE
      raise ::File::Error.from_winerror("Error opening file with mode '#{mode}'", file: filename)
    end
    {handle, overlapped, append}
  end

  def self.mktemp(prefix : String?, suffix : String?, dir : String) : {LibC::HANDLE, String}
    path = "#{dir}#{::File::SEPARATOR}#{prefix}.#{::Random::Secure.hex}#{suffix}"

    handle = LibC.CreateFileW(
      to_windows_path(path),
      LibC::GENERIC_READ | LibC::GENERIC_WRITE,
      LibC::FILE_SHARE_READ | LibC::FILE_SHARE_WRITE | LibC::FILE_SHARE_DELETE,
      nil,
      LibC::CREATE_NEW,
      LibC::FILE_ATTRIBUTE_NORMAL | LibC::FILE_FLAG_OVERLAPPED,
      LibC::HANDLE.null
    )
    if handle == LibC::INVALID_HANDLE_VALUE
      raise ::File::Error.from_winerror("Error creating temporary file", file: path)
    end

    {handle, path}
  end

  NOT_FOUND_ERRORS = {
    WinError::ERROR_FILE_NOT_FOUND,
    WinError::ERROR_PATH_NOT_FOUND,
    WinError::ERROR_INVALID_NAME,
  }

  REPARSE_TAG_NAME_SURROGATE_MASK = 1 << 29

  private def self.check_not_found_error(message, path)
    error = WinError.value
    if NOT_FOUND_ERRORS.includes? error
      return nil
    else
      raise ::File::Error.from_winerror(message, error, file: path)
    end
  end

  def self.info?(path : String, follow_symlinks : Bool) : ::File::Info?
    winpath = to_windows_path(path)

    unless follow_symlinks
      # First try using GetFileAttributes to check if it's a reparse point
      file_attributes = uninitialized LibC::WIN32_FILE_ATTRIBUTE_DATA
      ret = LibC.GetFileAttributesExW(
        winpath,
        LibC::GET_FILEEX_INFO_LEVELS::GetFileExInfoStandard,
        pointerof(file_attributes)
      )
      return check_not_found_error("Unable to get file info", path) if ret == 0

      if file_attributes.dwFileAttributes.bits_set? LibC::FILE_ATTRIBUTE_REPARSE_POINT
        # Could be a symlink, retrieve its reparse tag with FindFirstFile
        handle = LibC.FindFirstFileW(winpath, out find_data)
        return check_not_found_error("Unable to get file info", path) if handle == LibC::INVALID_HANDLE_VALUE

        if LibC.FindClose(handle) == 0
          raise RuntimeError.from_winerror("FindClose")
        end

        if find_data.dwReserved0.bits_set? REPARSE_TAG_NAME_SURROGATE_MASK
          return FileInfo.new(find_data)
        end
      end
    end

    handle = LibC.CreateFileW(
      to_windows_path(path),
      LibC::FILE_READ_ATTRIBUTES,
      LibC::FILE_SHARE_READ | LibC::FILE_SHARE_WRITE | LibC::FILE_SHARE_DELETE,
      nil,
      LibC::OPEN_EXISTING,
      LibC::FILE_FLAG_BACKUP_SEMANTICS,
      LibC::HANDLE.null
    )

    return check_not_found_error("Unable to get file info", path) if handle == LibC::INVALID_HANDLE_VALUE

    begin
      if LibC.GetFileInformationByHandle(handle, out file_info) == 0
        raise ::File::Error.from_winerror("Unable to get file info", file: path)
      end

      FileInfo.new(file_info, LibC::FILE_TYPE_DISK)
    ensure
      LibC.CloseHandle(handle)
    end
  end

  def self.info(path, follow_symlinks)
    info?(path, follow_symlinks) || raise ::File::Error.from_winerror("Unable to get file info", file: path)
  end

  def self.exists?(path)
    accessible?(path, 0)
  end

  def self.readable?(path) : Bool
    accessible?(path, 4)
  end

  def self.writable?(path) : Bool
    accessible?(path, 2)
  end

  def self.executable?(path) : Bool
    raise NotImplementedError.new("File.executable?")
  end

  private def self.accessible?(path, mode)
    LibC._waccess_s(to_windows_path(path), mode) == 0
  end

  def self.chown(path : String, uid : Int32, gid : Int32, follow_symlinks : Bool) : Nil
    raise NotImplementedError.new("File.chown")
  end

  def self.chmod(path : String, mode : Int32 | ::File::Permissions) : Nil
    mode = ::File::Permissions.new(mode) unless mode.is_a? ::File::Permissions

    # TODO: dereference symlinks

    attributes = LibC.GetFileAttributesW(to_windows_path(path))
    if attributes == LibC::INVALID_FILE_ATTRIBUTES
      raise ::File::Error.from_winerror("Error changing permissions", file: path)
    end

    # Only the owner writable bit is used, since windows only supports
    # the read only attribute.
    if mode.owner_write?
      attributes &= ~LibC::FILE_ATTRIBUTE_READONLY
    else
      attributes |= LibC::FILE_ATTRIBUTE_READONLY
    end

    if LibC.SetFileAttributesW(to_windows_path(path), attributes) == 0
      raise ::File::Error.from_winerror("Error changing permissions", file: path)
    end
  end

  def self.delete(path : String) : Nil
    if LibC._wunlink(to_windows_path(path)) != 0
      raise ::File::Error.from_errno("Error deleting file", file: path)
    end
  end

  def self.real_path(path : String) : String
    # TODO: read links using https://msdn.microsoft.com/en-us/library/windows/desktop/aa364571(v=vs.85).aspx
    win_path = to_windows_path(path)

    real_path = System.retry_wstr_buffer do |buffer, small_buf|
      len = LibC.GetFullPathNameW(win_path, buffer.size, buffer, nil)
      if 0 < len < buffer.size
        break String.from_utf16(buffer[0, len])
      elsif small_buf && len > 0
        next len
      else
        raise ::File::Error.from_winerror("Error resolving real path", file: path)
      end
    end

    unless exists? real_path
      raise ::File::Error.from_errno("Error resolving real path", Errno::ENOENT, file: path)
    end

    real_path
  end

  def self.link(old_path : String, new_path : String) : Nil
    if LibC.CreateHardLinkW(to_windows_path(new_path), to_windows_path(old_path), nil) == 0
      raise ::File::Error.from_winerror("Error creating hard link", file: old_path, other: new_path)
    end
  end

  def self.symlink(old_path : String, new_path : String) : Nil
    # TODO: support directory symlinks (copy Go's stdlib logic here)
    if LibC.CreateSymbolicLinkW(to_windows_path(new_path), to_windows_path(old_path), 0) == 0
      raise ::File::Error.from_winerror("Error creating symbolic link", file: old_path, other: new_path)
    end
  end

  def self.readlink(path) : String
    raise NotImplementedError.new("readlink")
  end

  def self.rename(old_path : String, new_path : String) : Nil
    if LibC.MoveFileExW(to_windows_path(old_path), to_windows_path(new_path), LibC::MOVEFILE_REPLACE_EXISTING) == 0
      raise ::File::Error.from_winerror("Error renaming file", file: old_path, other: new_path)
    end
  end

  def self.utime(access_time : ::Time, modification_time : ::Time, path : String) : Nil
    atime = Crystal::System::Time.to_filetime(access_time)
    mtime = Crystal::System::Time.to_filetime(modification_time)
    handle = LibC.CreateFileW(
      to_windows_path(path),
      LibC::FILE_WRITE_ATTRIBUTES,
      LibC::FILE_SHARE_READ | LibC::FILE_SHARE_WRITE | LibC::FILE_SHARE_DELETE,
      nil,
      LibC::OPEN_EXISTING,
      LibC::FILE_ATTRIBUTE_NORMAL,
      LibC::HANDLE.null
    )
    if handle == LibC::INVALID_HANDLE_VALUE
      raise ::File::Error.from_winerror("Error setting time on file", file: path)
    end
    begin
      if LibC.SetFileTime(handle, nil, pointerof(atime), pointerof(mtime)) == 0
        raise ::File::Error.from_winerror("Error setting time on file", file: path)
      end
    ensure
      LibC.CloseHandle(handle)
    end
  end

  private def system_truncate(size : Int) : Nil
    offset = uninitialized LibC::LARGE_INTEGER
    offset.quadPart = size
    if LibC.SetFilePointerEx(fd, offset, out _, LibC::FILE_BEGIN) == 0
      raise ::File::Error.from_winerror("Error truncating file", file: path)
    end
    if LibC.SetEndOfFile(fd) == 0
      raise ::File::Error.from_winerror("Error truncating file", file: path)
    end
  end

  private def system_flock_shared(blocking : Bool) : Nil
    raise NotImplementedError.new("File#flock_shared")
  end

  private def system_flock_exclusive(blocking : Bool) : Nil
    raise NotImplementedError.new("File#flock_exclusive")
  end

  private def system_flock_unlock : Nil
    raise NotImplementedError.new("File#flock_unlock")
  end

  private def self.to_windows_path(path : String) : LibC::LPWSTR
    path.check_no_null_byte.to_utf16.to_unsafe
  end

  private def system_fsync(flush_metadata = true) : Nil
    if LibC.FlushFileBuffers(fd) == 0
      raise IO::Error.from_winerror("Error syncing file")
    end
  end
end
