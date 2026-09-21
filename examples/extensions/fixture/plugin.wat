(module
  (memory (export "memory") 1)
  (data (i32.const 1024) "{\"ok\":true,\"effects\":[]}")

  (func (export "alloc") (param i32) (result i32)
    (i32.const 2048)
  )

  (func (export "cri_call") (param i32 i32) (result i32)
    (i32.const 1024)
  )

  (func (export "cri_result_len") (result i32)
    (i32.const 24)
  )

  (func (export "free") (param i32 i32))
  (func (export "cri_free_result") (param i32 i32))
)