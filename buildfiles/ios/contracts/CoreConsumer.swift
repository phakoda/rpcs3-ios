import RPCS3Core

public func rpcs3CoreConsumerContract() -> Bool {
    let capabilities = rpcs3_ios_core_query_capabilities()
    let operation = rpcs3_ios_core_query_operation_status()
    return capabilities.api_major == 0 &&
        capabilities.api_minor == 5 &&
        operation.struct_size == MemoryLayout<rpcs3_ios_core_operation_status>.size
}
