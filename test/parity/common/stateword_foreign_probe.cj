package rt.common

// Test-only declarations supplied when StateWord.cj is built without the rest of rt.common.
// The full production package reuses the identical declarations already owned by RegionInfo.cj
// and Register.cj; this file contributes no definition, storage, or behavior.
foreign {
    func RtFatal(message: CString): Unit
}
