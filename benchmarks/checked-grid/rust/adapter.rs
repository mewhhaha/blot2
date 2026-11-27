#[cfg(target_arch = "wasm32")]
mod guest {

    use std::cell::RefCell;

    thread_local! {
        static INPUT: RefCell<Vec<u32>> = const { RefCell::new(Vec::new()) };
        static OUTPUT: RefCell<[u32; 3]> = const { RefCell::new([2, 0, 0]) };
    }

    #[export_name = "squid:reset"]
    pub extern "C" fn reset(_: u32) -> u32 {
        INPUT.with(|input| input.borrow_mut().clear());
        0
    }

    #[export_name = "squid:allocate"]
    pub extern "C" fn allocate(bytes: u32) -> u32 {
        assert!(bytes >= 4 && bytes % 4 == 0);
        INPUT.with(|input| {
            let mut data = input.borrow_mut();
            data.resize((bytes / 4) as usize, 0);
            data.as_mut_ptr() as u32
        })
    }

    #[export_name = "squid:finish_invocation"]
    pub extern "C" fn finish() -> u32 {
        0
    }

    #[export_name = "solve"]
    pub extern "C" fn solve(ptr: u32) -> u32 {
        let (data, len) = INPUT.with(|input| {
            let data = input.borrow();
            assert_eq!(ptr, data.as_ptr() as u32);
            assert_eq!(data[0] as usize, data.len() - 1);
            (data[1..].as_ptr(), data.len() - 1)
        });
        // SAFETY: solve_words has no host calls and cannot access this private
        // thread-local buffer. End the RefCell borrow first so a Wasm trap
        // cannot strand its borrow flag when the host reuses this instance.
        let (a, b) = super::super::solve_words(unsafe { std::slice::from_raw_parts(data, len) });
        OUTPUT.with(|output| {
            let mut packet = output.borrow_mut();
            *packet = [2, a, b];
            packet.as_ptr() as u32
        })
    }
}
