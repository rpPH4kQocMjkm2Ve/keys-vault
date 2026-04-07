.PHONY: install uninstall reinstall install-conf man clean clean-mocks test build keys-vault

PREFIX     = /usr
SYSCONFDIR = /etc
DESTDIR    =
pkgname    = keys-vault

BINDIR       = $(PREFIX)/bin
SHAREDIR     = $(PREFIX)/share
MANDIR       = $(SHAREDIR)/man
ZSH_COMPDIR  = $(SHAREDIR)/zsh/site-functions
BASH_COMPDIR = $(SHAREDIR)/bash-completion/completions
UNITDIR      = $(PREFIX)/lib/systemd/user
LICENSEDIR   = $(SHAREDIR)/licenses/$(pkgname)

ASMC         = nasm
ASM          = ld
SRC_DIR      = src

MANPAGES = man/keys-vault.1

# Build assembly source
build: keys-vault

keys-vault: $(SRC_DIR)/keys-vault.asm
	$(ASMC) -f elf64 -o $@.o $(SRC_DIR)/keys-vault.asm
	$(ASM) -o $@ $@.o
	@rm -f $@.o
	@echo "Built keys-vault (x86_64 assembly)"

man: $(MANPAGES)

man/%.1: man/%.1.md
	pandoc -s -t man -o $@ $<

clean:
	rm -f $(MANPAGES) keys-vault keys-vault.o

clean-mocks:
	@for cmd in gocryptfs secret-tool fusermount mkdir mountpoint; do \
		if [[ -f /usr/bin/$$cmd.backup_test ]]; then \
			mv /usr/bin/$$cmd.backup_test /usr/bin/$$cmd; \
		elif [[ -f /usr/bin/$$cmd ]]; then \
			rm -f /usr/bin/$$cmd; \
		fi; \
	done
	@echo "Cleaned test mock scripts from /usr/bin/"

UNIT_TESTS = \
	tests/test_config.sh \
	tests/test_cli.sh \
	tests/test_commands.sh

test: build
	@for t in $(UNIT_TESTS); do \
		echo ""; \
		echo "━━━ $$t ━━━"; \
		bash "$$t" || exit 1; \
	done

install: build
	install -Dm755 keys-vault $(DESTDIR)$(BINDIR)/keys-vault

	install -Dm644 systemd/user/keys-vault.service \
		$(DESTDIR)$(UNITDIR)/keys-vault.service

	install -Dm644 completions/_keys-vault \
		$(DESTDIR)$(ZSH_COMPDIR)/_keys-vault
	install -Dm644 completions/keys-vault.bash \
		$(DESTDIR)$(BASH_COMPDIR)/keys-vault

	install -Dm644 man/keys-vault.1 $(DESTDIR)$(MANDIR)/man1/keys-vault.1

	install -Dm644 LICENSE $(DESTDIR)$(LICENSEDIR)/LICENSE

	@if [ ! -f "$(DESTDIR)$(SYSCONFDIR)/keys-vault.conf" ]; then \
		install -Dm644 etc/keys-vault.conf \
			"$(DESTDIR)$(SYSCONFDIR)/keys-vault.conf"; \
		echo "Installed default config"; \
	else \
		echo "Config exists, skipping (see etc/keys-vault.conf for defaults)"; \
	fi

uninstall:
	rm -f  $(DESTDIR)$(BINDIR)/keys-vault
	rm -f  $(DESTDIR)$(UNITDIR)/keys-vault.service
	rm -f  $(DESTDIR)$(ZSH_COMPDIR)/_keys-vault
	rm -f  $(DESTDIR)$(BASH_COMPDIR)/keys-vault
	rm -f  $(DESTDIR)$(MANDIR)/man1/keys-vault.1
	rm -rf $(DESTDIR)$(LICENSEDIR)/
	@echo "Note: $(SYSCONFDIR)/keys-vault.conf preserved. Remove manually if needed."

reinstall: uninstall install

install-conf:
	install -Dm644 etc/keys-vault.conf $(DESTDIR)$(SYSCONFDIR)/keys-vault.conf
	@echo "Config force-installed."
