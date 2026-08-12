#ifndef C_MACH_SUPPORT_H
#define C_MACH_SUPPORT_H

#include <mach/host_info.h>
#include <mach/vm_page_size.h>

/// HOST_VM_INFO64_COUNTはSwiftへimportできないため、公式マクロの値をC経由で返す。
mach_msg_type_number_t memorybar_host_vm_info64_count(void);

/// vm_kernel_page_sizeは可変グローバルとしてimportされ、Swift 6の並行性チェックに
/// 抵触する。値は起動後不変なのでC経由で読み出す。
/// vm_statistics64のページカウントはこのカーネルページ単位。
vm_size_t memorybar_kernel_page_size(void);

#endif
