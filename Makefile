install:
	mkdir -p ~/bin ~/Library/LaunchAgents ~/Library/Logs
	cp diskspace_guard.sh ~/bin/
	chmod +x ~/bin/diskspace_guard.sh
	cp com.craig.diskspace-guard.plist ~/Library/LaunchAgents/
	launchctl unload ~/Library/LaunchAgents/com.craig.diskspace-guard.plist 2>/dev/null || true
	launchctl load  ~/Library/LaunchAgents/com.craig.diskspace-guard.plist

install-cloud:
	mkdir -p ~/bin ~/Library/LaunchAgents ~/Library/Logs
	cp cloudspace_*.sh ~/bin/
	chmod +x ~/bin/cloudspace_*.sh
	cp com.craig.cloudspace-report.plist ~/Library/LaunchAgents/
	launchctl unload ~/Library/LaunchAgents/com.craig.cloudspace-report.plist 2>/dev/null || true
	launchctl load  ~/Library/LaunchAgents/com.craig.cloudspace-report.plist

uninstall:
	launchctl unload ~/Library/LaunchAgents/com.craig.diskspace-guard.plist 2>/dev/null || true
	launchctl unload ~/Library/LaunchAgents/com.craig.cloudspace-report.plist 2>/dev/null || true
	rm -f ~/Library/LaunchAgents/com.craig.diskspace-guard.plist
	rm -f ~/Library/LaunchAgents/com.craig.cloudspace-report.plist
	rm -f ~/bin/diskspace_guard.sh ~/bin/cloudspace_*.sh
