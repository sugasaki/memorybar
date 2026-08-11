#ifndef C_MACH_SUPPORT_H
#define C_MACH_SUPPORT_H

#include <mach/host_info.h>

/// HOST_VM_INFO64_COUNTはSwiftへimportできないため、公式マクロの値をC経由で返す。
mach_msg_type_number_t truemem_host_vm_info64_count(void);

#endif
