#include "CMachSupport.h"

mach_msg_type_number_t truemem_host_vm_info64_count(void) {
    return HOST_VM_INFO64_COUNT;
}

vm_size_t truemem_kernel_page_size(void) {
    return vm_kernel_page_size;
}
