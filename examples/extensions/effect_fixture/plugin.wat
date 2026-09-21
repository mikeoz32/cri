(module
  (memory (export "memory") 1)
  (global $state (mut i32) (i32.const 0))
  (data (i32.const 1024) "{\"ok\":true,\"effects\":[{\"type\":\"http.request\",\"url\":\"https://example.com\"}]}")
  (data (i32.const 1400) "{\"ok\":true,\"result\":{\"resumed\":true},\"effects\":[]}")

  (func (export "alloc") (param i32) (result i32)
    (i32.const 2048)
  )

  (func (export "cri_call") (param i32 i32) (result i32)
    (i32.const 1024)
  )

  (func (export "cri_resume") (param i32 i32) (result i32)
    (global.set $state (i32.const 1))
    (i32.const 1400)
  )

  (func (export "cri_result_len") (result i32)
    (if (result i32) (global.get $state)
      (then (i32.const 50))
      (else (i32.const 75))
    )
  )

  (func (export "free") (param i32 i32))
  (func (export "cri_free_result") (param i32 i32))
)