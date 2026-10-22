install:
	mkdir -p ~/bin ~/Library/LaunchAgents ~/Library/Logs
	cp diskspace_guard.sh ~/bin/
	chmod +x ~/bin/diskspace_guard.sh
	sed "s|\$${HOME}|$(HOME)|g" com.craig.diskspace-guard.plist > ~/Library/LaunchAgents/com.craig.diskspace-guard.plist
	launchctl unload ~/Library/LaunchAgents/com.craig.diskspace-guard.plist 2>/dev/null || true
	launchctl load  ~/Library/LaunchAgents/com.craig.diskspace-guard.plist

install-cloud:
	mkdir -p ~/bin ~/Library/LaunchAgents ~/Library/Logs
	cp cloudspace_report.sh cloudspace_evict.sh ~/bin/
	chmod +x ~/bin/cloudspace_report.sh ~/bin/cloudspace_evict.sh
	sed "s|\$${HOME}|$(HOME)|g" com.craig.cloudspace-report.plist > ~/Library/LaunchAgents/com.craig.cloudspace-report.plist
	launchctl unload ~/Library/LaunchAgents/com.craig.cloudspace-report.plist 2>/dev/null || true
	launchctl load  ~/Library/LaunchAgents/com.craig.cloudspace-report.plist

uninstall:
	launchctl unload ~/Library/LaunchAgents/com.craig.diskspace-guard.plist 2>/dev/null || true
	launchctl unload ~/Library/LaunchAgents/com.craig.cloudspace-report.plist 2>/dev/null || true
	rm -f ~/Library/LaunchAgents/com.craig.diskspace-guard.plist
	rm -f ~/Library/LaunchAgents/com.craig.cloudspace-report.plist
	rm -f ~/bin/diskspace_guard.sh ~/bin/cloudspace_report.sh ~/bin/cloudspace_evict.sh
