import qankuro
import qankuro.validators as Valid

Playbook {
	id: root

	property string qtVersion: '6.6'
	property path qtDir: isWin? 'C:/Qt' : '/opt/Qt'
	property bool configureQbs: true
	property bool setDefaultQbsProfile: true

	readonly property bool isWin: sys.os === SystemInfo.OS.Windows
	readonly property bool isMac: sys.os === SystemInfo.OS.MacOS

	SystemInfo { id: sys }

	Pip { names: ['pipx'] }
	Pipx { names: ['aqtinstall'] }

	Homebrew {
		names: ['qbs']
		ensure: Valid.Version {
			version: Valid.Version.Latest
		}
	}

	Group {
		readonly property string hostOs: isMac? 'mac' : sys.os.toString()

		Command {
			id: latestVersion
			description: 'Get the latest available version'

			readonly property string result: stdout.trim()

			cmd: `aqt list-qt ${hostOs} desktop --spec ${qtVersion} --latest-version`
		}

		Command {
			id: installQt
			description: `Install desktop Qt ${latestVersion.result}`

			readonly property string arch: isWin? 'win64_msvc2019_64' : ''
			readonly property string ext: isWin? '.exe' : ''
			readonly property path qmakePath: path`${qtDir}/${latestVersion.result}/${subdir}/bin/qmake${ext}`
			readonly property string subdir: {
				switch (sys.os) {
				case SystemInfo.OS.Windows:
					return arch.replace(/^win_/, '')
				case SystemInfo.OS.MacOS:
					return 'macos'
				default:
					return 'gcc_64'
				}
			}

			cmd: `
				aqt install-qt ${hostOs} desktop ${latestVersion.result} ${arch}
					--modules all
					--outputdir ${qtDir}
			`

			ensure: Value.Path {
				path: qmakePath
				mode: Valid.Path.Exists
			}
		}
	}

	Group {
		when: configureQbs

		readonly property string system: isWin? '--system' : ''

		readonly property string qbsProfile: {
			const [major, minor] = qtVersion.split('.')
			return `Qt${major}${minor}`.replace(/[\s\.]/), '')
		}

		Command {
			description: 'Autodetect toolchains'
			cmd: `qbs setup-toolchains ${system} --detect`

			ensure: Valid.Command {
				cmd: 'qbs config --list profiles'
				validate: ({stdout}) => {
					return stdout.trim().length !== 0
				}
			}
		}

		Group {
			description: 'Set up Qt in Qbs'

			Command {
				description: 'Create Qbs profile for Qt'
				cmd: `qbs setup-qt ${system} ${installQt.qmakePath} ${qbsProfile}`

				ensure: Valid.Command {
					cmd: `qbs config profiles.${qbsProfile}`
					validate: ({stdout}) => {
						return stdout.trim().length !== 0
					}
				}
			}

			Command {
				description: 'Set base profile for Qt'

				readonly property string baseProfile: {
					switch (sys.os) {
					case SystemInfo.OS.Windows:
						return 'MSVC2022-x64'
					case SystemInfo.OS.MacOS:
						return 'xcode-macosx-arm64'
					default:
						return 'gcc'
					}
				}

				cmd: `qbs config ${system} profiles.${qbsProfile}.baseProfile ${baseProfile}`

				ensure: Valid.Command {
					cmd: `qbs config profiles.${qbsProfile}.baseProfile`
					validate: ({stdout}) => {
						return stdout.trim().length !== 0
					}
				}
			}

			Command {
				description: 'Set the default profile'

				cmd: `qbs config ${system} defaultProfile ${qbsProfile}`

				ensure: Valid.Command {
					cmd: `qbs config defaultProfile`
					validate: ({stdout}) => {
						return stdout.trim().length !== 0
					}
				}
			}
		}
	}
}
