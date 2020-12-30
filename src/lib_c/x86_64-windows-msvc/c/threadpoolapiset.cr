require "c/winnt"

lib LibC
  # opaque pointers.
  type PTP_CALLBACK_INSTANCE = Void*
  type PTP_POOL = Void*
  type PTP_CLEANUP_GROUP = Void*

  alias TP_VERSION = DWORD
  alias PTP_CLEANUP_GROUP_CANCEL_CALLBACK = Void*, Void* ->
  alias PTP_SIMPLE_CALLBACK = PTP_CALLBACK_INSTANCE, Void* ->

  enum TP_CALLBACK_PRIORITY
    TP_CALLBACK_PRIORITY_HIGH
    TP_CALLBACK_PRIORITY_NORMAL
    TP_CALLBACK_PRIORITY_LOW
    TP_CALLBACK_PRIORITY_INVALID
    TP_CALLBACK_PRIORITY_COUNT   = TP_CALLBACK_PRIORITY_INVALID
  end

  struct TP_CALLBACK_ENVIRON_V3
    version : TP_VERSION
    pool : PTP_POOL
    cleanupGroup : PTP_CLEANUP_GROUP
    cleanupGroupCancelCallback : PTP_CLEANUP_GROUP_CANCEL_CALLBACK
    raceDll : Void*
    activationContext : Void*
    finalizationCallback : PTP_SIMPLE_CALLBACK
    flags : DWORD
    callbackPriority : TP_CALLBACK_PRIORITY
    size : DWORD
  end

  alias PTP_CALLBACK_ENVIRON = TP_CALLBACK_ENVIRON_V3*

  fun TrySubmitThreadpoolCallback(pfns : PTP_SIMPLE_CALLBACK, pv : Void*, pcbe : PTP_CALLBACK_ENVIRON) : BOOL
  fun CallbackMayRunLong(pci : PTP_CALLBACK_INSTANCE) : BOOL
end
