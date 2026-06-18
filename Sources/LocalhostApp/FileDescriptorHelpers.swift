import Darwin

extension Int32 {
    func setNonBlocking() {
        updateFlags { $0 | O_NONBLOCK }
    }

    func setBlocking() {
        updateFlags { $0 & ~O_NONBLOCK }
    }

    private func updateFlags(_ update: (Int32) -> Int32) {
        let flags = fcntl(self, F_GETFL, 0)
        guard flags >= 0 else {
            return
        }

        _ = fcntl(self, F_SETFL, update(flags))
    }
}
