# Crystal's current WASM toolchain exports explicitly typed `fun` functions.
# The build step must pass these names to wasm-ld with --export.
fun alloc(size : Int32) : Int32
  CriSDK::Runtime.alloc(size)
end

fun cri_free(pointer : Int32, size : Int32)
  CriSDK::Runtime.free(pointer, size)
end

fun cri_call(input_pointer : Int32, input_length : Int32) : Int32
  CriSDK::Runtime.call(input_pointer, input_length)
end

fun cri_resume(input_pointer : Int32, input_length : Int32) : Int32
  CriSDK::Runtime.resume(input_pointer, input_length)
end

fun cri_result_len : Int32
  CriSDK::Runtime.result_len
end

fun cri_free_result(pointer : Int32, size : Int32)
  CriSDK::Runtime.free_result(pointer, size)
end
