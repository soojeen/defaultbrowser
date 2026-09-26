BIN ?= defaultbrowser
PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin

CC ?= gcc
CFLAGS ?= -O2

.PHONY: all install uninstall clean

all: $(BIN)

$(BIN): src/main.m
	$(CC) -o $(BIN) $(CFLAGS) -mmacosx-version-min=10.15 -framework Foundation -framework ApplicationServices -framework AppKit src/main.m

install: $(BIN)
	install -d $(DESTDIR)$(BINDIR)
	install -m 755 $(BIN) $(DESTDIR)$(BINDIR)

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/$(BIN)

clean:
	rm -f $(BIN)
