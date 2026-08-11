#include "CMachSupport.h"

mach_msg_type_number_t truemem_host_vm_info64_count(void) {
    return HOST_VM_INFO64_COUNT;
}
