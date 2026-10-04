.PHONY: build run install stop clean

INSTALL_PATH = /Applications/NotchPlayer.app

build:
	./scripts/build-app.sh

run: build stop
	open build/NotchPlayer.app

# Copies the app to /Applications and registers it to open at login.
install: build stop
	rm -rf $(INSTALL_PATH)
	cp -R build/NotchPlayer.app $(INSTALL_PATH)
	open $(INSTALL_PATH) --args --enable-login-item

stop:
	-pkill -x NotchPlayer

clean:
	rm -rf build .build
