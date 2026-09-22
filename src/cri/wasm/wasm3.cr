{% if flag?(:wasm3) || flag?(:Wasm3) %}
  @[Link("m3")]
  lib LibWasm3
    fun m3_NewEnvironment : Pointer(Void)
    fun m3_FreeEnvironment(environment : Pointer(Void))

    fun m3_NewRuntime(environment : Pointer(Void), stack_size : UInt32, userdata : Pointer(Void)) : Pointer(Void)
    fun m3_FreeRuntime(runtime : Pointer(Void))
    fun m3_SetGasLimit(runtime : Pointer(Void), gas : Float64)

    fun m3_ParseModule(environment : Pointer(Void), out_module : Pointer(Pointer(Void)), bytes : Pointer(UInt8), size : UInt32) : Pointer(UInt8)
    fun m3_LoadModule(runtime : Pointer(Void), module : Pointer(Void)) : Pointer(UInt8)

    fun m3_FindFunctionIn(out_function : Pointer(Pointer(Void)), module : Pointer(Void), name : Pointer(UInt8)) : Pointer(UInt8)
    fun m3_Call(function : Pointer(Void), argc : UInt32, argv : Pointer(Pointer(Void))) : Pointer(UInt8)
    fun m3_GetResults(function : Pointer(Void), retc : UInt32, retptrs : Pointer(Pointer(Void))) : Pointer(UInt8)

    fun m3_GetMemory(module : Pointer(Void), out_size : Pointer(LibC::SizeT), index : UInt32) : Pointer(UInt8)
  end
{% end %}
