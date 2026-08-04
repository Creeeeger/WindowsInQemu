#define _GNU_SOURCE

#include <dlfcn.h>
#include <stdarg.h>
#include <stdint.h>
#include <sys/ioctl.h>
#include <linux/kvm.h>

typedef int (*ioctl_fn)(int, int, ...);

int ioctl(int fd, int request, ...)
{
	static ioctl_fn real_ioctl;
	unsigned long arg;
	va_list ap;

	va_start(ap, request);
	arg = va_arg(ap, unsigned long);
	va_end(ap);

	if (!real_ioctl)
		real_ioctl = (ioctl_fn)dlsym(RTLD_NEXT, "ioctl");

	if (request == KVM_SET_USER_MEMORY_REGION) {
		const struct kvm_userspace_memory_region *region;
		struct kvm_userspace_memory_region executable_flash;

		region = (const struct kvm_userspace_memory_region *)(uintptr_t)arg;
		if (region &&
		    region->guest_phys_addr == 0 &&
		    region->memory_size == 0x04000000ULL &&
		    (region->flags & KVM_MEM_READONLY)) {
			executable_flash = *region;
			executable_flash.flags &= ~KVM_MEM_READONLY;
			return real_ioctl(fd, request, &executable_flash);
		}
	}

	return real_ioctl(fd, request, arg);
}
