// from: http://lists.macosforge.org/pipermail/macports-dev/2011-June/015071.html

#include <inttypes.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>

#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/mman.h>

#include <err.h>
#include <string.h>

#include <mach-o/arch.h>
#include <mach-o/loader.h>
#include <mach-o/fat.h>

#include <libkern/OSAtomic.h>

typedef struct macho_input {
    const void *data;
    size_t length;
} macho_input_t;

/* Verify that the given range is within bounds. */
static const void *macho_read (macho_input_t *input, const void *address, size_t length) {
    if ((((uint8_t *) address) - ((uint8_t *) input->data)) + length > input->length) {
        warnx("Short read parsing Mach-O input");
        return NULL;
    }

    return address;
}

/* Verify that address + offset + length is within bounds. */
static const void *macho_offset (macho_input_t *input, const void *address, size_t offset, size_t length) {
    void *result = ((uint8_t *) address) + offset;
    return macho_read(input, result, length);
}

/* return a human readable formatted version number. the result must be free()'d. */
char *macho_format_dylib_version (uint32_t version) {
    char *result;
    asprintf(&result, "%"PRIu32".%"PRIu32".%"PRIu32, (version >> 16) & 0xFF, (version >> 8) & 0xFF, version & 0xFF);
    return result;
}

/* Some byteswap wrappers */
static uint32_t macho_swap32 (uint32_t input) {
    return OSSwapInt32(input);
}

static uint32_t macho_nswap32(uint32_t input) {
    return input;
}

/* Parse a Mach-O header */
bool parse_macho (macho_input_t *input) {
    /* Read the file type. */
    const uint32_t *magic = macho_read(input, input->data, sizeof(uint32_t));
    if (magic == NULL)
        return false;

    /* Parse the Mach-O header */
    bool m64 = false;
    bool universal = false;
    uint32_t (*swap32)(uint32_t) = macho_nswap32;

    const struct mach_header *header;
    const struct mach_header_64 *header64;
    size_t header_size;
    const struct fat_header *fat_header;

    switch (*magic) {
        case MH_CIGAM:
            swap32 = macho_swap32;
            // Fall-through

        case MH_MAGIC:

            header_size = sizeof(*header);
            header = macho_read(input, input->data, header_size);
            if (header == NULL) {
                return false;
            }
            printf("Type: Mach-O 32-bit\n");
            break;


        case MH_CIGAM_64:
            swap32 = macho_swap32;
            // Fall-through

        case MH_MAGIC_64:
            header_size = sizeof(*header64);
            header64 = macho_read(input, input->data, sizeof(*header64));
            if (header64 == NULL)
                return false;

            /* The 64-bit header is a direct superset of the 32-bit header */
            header = (struct mach_header *) header64;

            printf("Type: Mach-O 64-bit\n");
            m64 = true;
            break;

        case FAT_CIGAM:
        case FAT_MAGIC:
            fat_header = macho_read(input, input->data, sizeof(*fat_header));
            universal = true;
            printf("Type: Universal\n");
            break;

        default:
            warnx("Unknown Mach-O magic: 0x%" PRIx32 "", *magic);
            return false;
    }

    /* Parse universal file. */
    if (universal) {
        uint32_t nfat = OSSwapBigToHostInt32(fat_header->nfat_arch);
        const struct fat_arch *archs = macho_offset(input, fat_header, sizeof(struct fat_header), sizeof(struct fat_arch));
        if (archs == NULL)
            return false;

        printf("Architecture Count: %" PRIu32 "\n", nfat);
        for (uint32_t i = 0; i < nfat; i++) {
            const struct fat_arch *arch = macho_read(input, archs + i, sizeof(struct fat_arch));
            if (arch == NULL)
                return false;

            /* Fetch a pointer to the architecture's Mach-O header. */
            macho_input_t arch_input;
            arch_input.length = OSSwapBigToHostInt32(arch->size);
            arch_input.data = macho_offset(input, input->data, OSSwapBigToHostInt32(arch->offset), arch_input.length);
            if (arch_input.data == NULL)
                return false;

            /* Parse the architecture's Mach-O header */
            printf("\n");
            if (!parse_macho(&arch_input))
                return false;
        }

        return true;
    }

    /* Fetch the arch name */
    const NXArchInfo *archInfo = NXGetArchInfoFromCpuType(swap32(header->cputype), swap32(header->cpusubtype));
    if (archInfo != NULL) {
        printf("Architecture: %s\n", archInfo->name);
    }

    /* Parse the Mach-O load commands */
    const struct load_command *cmd = macho_offset(input, header, header_size, sizeof(struct load_command));
    if (cmd == NULL)
        return false;
    uint32_t ncmds = swap32(header->ncmds);

    /* Iterate over the load commands */
    for (uint32_t i = 0; i < ncmds; i++) {
        /* Load the full command */
        uint32_t cmdsize = swap32(cmd->cmdsize);
        cmd = macho_read(input, cmd, cmdsize);
        if (cmd == NULL)
            return false;

        /* Handle known types */
        uint32_t cmd_type = swap32(cmd->cmd);
        switch (cmd_type) {
            case LC_RPATH: {
                /* Fetch the path */
                if (cmdsize < sizeof(struct rpath_command)) {
                    warnx("Incorrect cmd size");
                    return false;
                }

                size_t pathlen = cmdsize - sizeof(struct rpath_command);
                const void *pathptr = macho_offset(input, cmd, sizeof(struct rpath_command), pathlen);
                if (pathptr == NULL)
                    return false;

                char *path = malloc(pathlen);
                strlcpy(path, pathptr, pathlen);
                printf("[rpath] path=%s\n", path);
                free(path);
                break;
            }

            case LC_ID_DYLIB:
            case LC_LOAD_WEAK_DYLIB:
            case LC_REEXPORT_DYLIB:
            case LC_LOAD_DYLIB: {
                const struct dylib_command *dylib_cmd = (const struct dylib_command *) cmd;

                /* Extract the install name */
                if (cmdsize < sizeof(struct dylib_command)) {
                    warnx("Incorrect name size");
                    return false;
                }

                size_t namelen = cmdsize - sizeof(struct dylib_command);
                const void *nameptr = macho_offset(input, cmd, sizeof(struct dylib_command), namelen);
                if (nameptr == NULL)
                    return false;

                char *name = malloc(namelen);
                strlcpy(name, nameptr, namelen);

                /* Print the dylib info */
                char *current_version = macho_format_dylib_version(swap32(dylib_cmd->dylib.current_version));
                char *compat_version = macho_format_dylib_version(swap32(dylib_cmd->dylib.compatibility_version));

                switch (cmd_type) {
                    case LC_ID_DYLIB:
                        printf("[dylib] ");
                        break;
                    case LC_LOAD_WEAK_DYLIB:
                        printf("[weak] ");
                        break;
                    case LC_LOAD_DYLIB:
                        printf("[load] ");
                        break;
                    case LC_REEXPORT_DYLIB:
                        printf("[reexport] ");
                        break;
                    default:
                        printf("[%"PRIx32"] ", cmd_type);
                        break;
                }

                /* This is a dyld library identifier */
                printf("install_name=%s (compatibility_version=%s, version=%s)\n", name, compat_version, current_version);

                free(name);
                free(current_version);
                free(compat_version);
                break;
            }

            default:
                break;
        }

        /* Load the next command */
        cmd = macho_offset(input, cmd, cmdsize, sizeof(struct load_command));
        if (cmd == NULL)
            return false;
    }

    return true;
}

int main (int argc, char *argv[]) {
    if (argc < 2) {
        errx(1, "Missing path to Mach-O binary");
    }

    /* Open the input file */
    const char *path = argv[1];
    int fd = open(path, O_RDONLY);
    if (fd < 0) {
        err(1, "%s", path);
    }

    struct stat stbuf;
    if (fstat(fd, &stbuf) != 0) {
        err(1, "fstat()");
    }

    /* mmap */
    void *data = mmap(NULL, stbuf.st_size, PROT_READ, MAP_FILE|MAP_PRIVATE, fd, 0);
    if (data == MAP_FAILED)
        err(1, "mmap()");

    /* Parse */
    macho_input_t input_file;
    input_file.data = data;
    input_file.length = stbuf.st_size;

    printf("Parsing: %s\n", path);
    if (!parse_macho(&input_file)) {
        errx(1, "Failed to parse file");
    }

    munmap(data, stbuf.st_size);
    close(fd);
    exit(0);
}

