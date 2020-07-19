require "c/io"
require "c/consoleapi"
require "c/namedpipeapi"

module Crystal::System::FileDescriptor
  @volatile_fd : Atomic(LibC::HANDLE)
  @current_pos : Int64?

  private def unbuffered_read(slice : Bytes)
    bytes_read = system_pread(slice, @current_pos)
    if current_pos = @current_pos
      @current_pos = current_pos + bytes_read
    end
    bytes_read
  end

  private def unbuffered_write(slice : Bytes)
    until slice.empty?
      offset = (@current_pos && @append) ? -1_i64 : @current_pos
      bytes_written = io_with_overlapped(offset) do |handle, overlapped|
        LibC.WriteFile(handle, slice, slice.size, nil, overlapped)
      end
      if bytes_written
        if current_pos = @current_pos
          if @append
            if LibC.GetFileSizeEx(fd, out size) == 0
              raise IO::Error.from_winerror("Unable to change the current position")
            end
            @current_pos = size.quadPart.to_i64
          else
            @current_pos = current_pos + bytes_written
          end
        end
        slice += bytes_written
      else
        winerror = WinError.value
        case winerror
        when WinError::ERROR_ACCESS_DENIED
          raise IO::Error.new "File not open for writing"
        else
          raise IO::Error.from_winerror("Error writing file", winerror)
        end
      end
    end
  end

  private def system_initialize(fd, @overlapped : Bool, @append : Bool = false)
    @current_pos = 0 if LibC.GetFileType(fd) == LibC::FILE_TYPE_DISK
  end

  # I/O with overlapped structure
  #
  # The block must do the followings.
  #  * use the passed parameters: LibC::HANDLE and a pointer of LibC::OVERLAPPED.
  #  * don't use the argument for receiving the number of bytes transferred.
  #    It is got from the OVERLAPPED structure.
  #  * return LibC::BOOL.
  #
  # This returns the number of bytes transferred on success.
  # nil on error. Check WinError.value to get the error code.
  private def io_with_overlapped(offset, &block) : LibC::DWORD?
    handle = fd
    ol = LibC::OVERLAPPED.new
    if offset
      ol.union.offset.offset = offset.to_u32!
      ol.union.offset.offsetHigh = (offset >> 32).to_u32!
    end
    preserve_errcode = false
    begin
      if @overlapped
        # handle with FILE_FLAG_OVERLAPPED
        ol.hEvent = LibC.CreateEventW(nil, true, false, nil)
        if ol.hEvent.null?
          raise RuntimeError.from_winerror("CreateEventW")
        end
        if yield(handle, pointerof(ol)) == 0
          if WinError.value == WinError::ERROR_IO_PENDING
            # TODO: Use I/O completion port to wait `ol.hEvent` in
            # the event loop after the event loop is ported to win32.
            if LibC.WaitForSingleObject(ol.hEvent, LibC::INFINITE) != 0
              raise RuntimeError.from_winerror("WaitForSingleObject")
            end
          else
            preserve_errcode = true
            return nil
          end
        end
      else
        # handle without FILE_FLAG_OVERLAPPED
        # It may be better to yield the block in another native thread
        # in order not to block the event loop after the event loop is
        # ported to win32.
        if yield(handle, pointerof(ol)) == 0
          return nil
        end
      end
      if LibC.GetOverlappedResult(handle, pointerof(ol), out bytes_transferred, true) == 0
        preserve_errcode = true
        return nil
      end
      bytes_transferred
    ensure
      unless ol.hEvent.null?
        saved_errcode = LibC.GetLastError if preserve_errcode
        LibC.CloseHandle(ol.hEvent)
        LibC.SetLastError(saved_errcode) if saved_errcode
      end
    end
  end

  protected def system_pread(buffer, offset)
    bytes_read = io_with_overlapped(offset) do |handle, overlapped|
      LibC.ReadFile(handle, buffer, buffer.size, nil, overlapped)
    end
    if bytes_read
      bytes_read
    else
      winerror = WinError.value
      case winerror
      when WinError::ERROR_ACCESS_DENIED
        raise IO::Error.new "File not open for reading"
      when WinError::ERROR_HANDLE_EOF
        0 # End of file
      when WinError::ERROR_BROKEN_PIPE
        0 # All write-side pipes have been closed.
      else
        raise IO::Error.from_winerror("Error reading file", winerror)
      end
    end
  end

  private def system_blocking?
    true
  end

  private def system_blocking=(blocking)
    raise NotImplementedError.new("Crystal::System::FileDescriptor#system_blocking=") unless blocking
  end

  private def system_close_on_exec?
    false
  end

  private def system_close_on_exec=(close_on_exec)
    raise NotImplementedError.new("Crystal::System::FileDescriptor#system_close_on_exec=") if close_on_exec
  end

  private def system_closed?
    false
  end

  private def system_info
    handle = fd

    file_type = LibC.GetFileType(handle)

    if file_type == LibC::FILE_TYPE_UNKNOWN
      error = WinError.value
      raise IO::Error.from_winerror("Unable to get info", error) unless error == WinError::ERROR_SUCCESS
    end

    if file_type == LibC::FILE_TYPE_DISK
      if LibC.GetFileInformationByHandle(handle, out file_info) == 0
        raise IO::Error.from_winerror("Unable to get info")
      end

      FileInfo.new(file_info, file_type)
    else
      FileInfo.new(file_type)
    end
  end

  private def system_seek(offset, whence : IO::Seek) : Nil
    if current_pos = @current_pos
      case whence
      when IO::Seek::Set
        current_pos = Int64.new(offset)
      when IO::Seek::Current
        current_pos = current_pos + offset
      when IO::Seek::End
        if LibC.GetFileSizeEx(fd, out size) == 0
          raise IO::Error.from_winerror("Unable to get size")
        end
        current_pos = (size.quadPart + offset).to_i64
      end
      if current_pos < 0
        raise IO::Error.new "Unable to seek: negative file position"
      end
      @current_pos = current_pos
    else
      raise IO::Error.new "Unable to seek: not a regular file"
    end
  end

  private def system_pos
    if current_pos = @current_pos
      current_pos
    else
      raise IO::Error.new "Unable to tell: not a regular file"
    end
  end

  private def system_tty?
    # GetConsoleMode succeeds only when fd is console.
    LibC.GetConsoleMode(fd, out _) != 0
  end

  private def system_reopen(other : IO::FileDescriptor)
    cur_proc = LibC.GetCurrentProcess
    if LibC.DuplicateHandle(cur_proc, other.fd, cur_proc, out new_handle, 0, true, LibC::DUPLICATE_SAME_ACCESS) == 0
      raise RuntimeError.from_winerror("DuplicateHandle")
    end
    old_handle = @volatile_fd.swap(new_handle)
    if LibC.CloseHandle(old_handle) == 0
      raise RuntimeError.from_winerror("Error closing old file handle")
    end

    # Mark the handle open, since we had to have dup'd a live handle.
    @closed = false
  end

  private def system_close
    file_descriptor_close
  end

  def file_descriptor_close
    # Clear the @volatile_fd before actually closing it in order to
    # reduce the chance of reading an outdated fd value
    _fd = @volatile_fd.swap(LibC::INVALID_HANDLE_VALUE)

    if LibC.CloseHandle(_fd) == 0
      raise RuntimeError.from_winerror("Error closing file")
    end
  end

  def self.pipe(read_blocking, write_blocking)
    if LibC.CreatePipe(out read, out write, nil, 8192) == 0
      raise IO::Error.from_winerror("Could not create pipe")
    end

    # Handles created by CreatePipe are opened without FILE_FLAG_OVERLAPPED.
    r = IO::FileDescriptor.new(read, read_blocking, overlapped: false)
    w = IO::FileDescriptor.new(write, write_blocking, overlapped: false)
    w.sync = true

    {r, w}
  end

  def self.pread(fd, buffer, offset)
    fd.system_pread(buffer, offset)
  end

  def self.from_stdio(fd)
    console_handle = false
    handle = LibC::HANDLE.new(LibC._get_osfhandle(fd))
    if handle != LibC::INVALID_HANDLE_VALUE
      if LibC.GetConsoleMode(handle, out _) != 0
        console_handle = true
      end
    end

    # Handles in file descriptors are not opened with FILE_FLAG_OVERLAPPED.
    io = IO::FileDescriptor.new(handle, overlapped: false)
    # Set sync or flush_on_newline as described in STDOUT and STDERR docs.
    # See https://crystal-lang.org/api/toplevel.html#STDERR
    if console_handle
      io.sync = true
    else
      io.flush_on_newline = true
    end
    io
  end
end
