import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: panel
    objectName: "audioSettings"
    required property var controller
    required property var audio
    required property color ink
    required property color muted
    required property color accent
    property bool expanded: false
    property int editedMoment: -1
    readonly property bool desktop: Qt.platform.os !== "android"
    readonly property var devices: audio.audioDevices || []
    readonly property var moments: audio.moments || []
    readonly property var presets: [qsTr("Ровный"), qsTr("Больше баса"), qsTr("Больше высоких"),
        qsTr("Вокал"), qsTr("Электроника"), qsTr("Рок"), qsTr("Хип-хоп")]
        .concat((audio.equalizerPresets || []).map(entry => entry.label))
    readonly property var frequencies: ["60", "250", "1k", "4k", "12k"]

    spacing: 8
    function clock(seconds) {
        const minutes = Math.floor(seconds / 60)
        return minutes + ":" + String(seconds % 60).padStart(2, "0")
    }
    function timestamp(ms) { return clock(Math.floor(ms / 1000)) }
    function editMoment(index, name) {
        editedMoment = index
        momentName.text = name
        momentName.forceActiveFocus()
    }

    Label {
        visible: panel.desktop
        color: panel.ink
        text: qsTr("Устройство вывода")
    }
    ComboBox {
        visible: panel.desktop
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        model: panel.devices.map(entry => entry.id ? entry.label : qsTr("Системное устройство"))
        currentIndex: Math.max(0, panel.devices.findIndex(entry => entry.id === panel.audio.audioDevice))
        Accessible.name: qsTr("Устройство вывода")
        onActivated: index => panel.controller.setAudioDevice(panel.devices[index].id)
    }
    Label {
        visible: panel.desktop && !!panel.audio.audioDeviceUnavailable
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        color: panel.muted
        text: qsTr("Выбранное устройство отключено. Используется системное.")
    }
    Label {
        visible: panel.desktop
        color: panel.ink
        text: qsTr("Плавный переход · %1 с").arg(panel.audio.crossfadeSeconds || 0)
    }
    Slider {
        visible: panel.desktop
        enabled: !!panel.audio.preloadEnabled
        Layout.fillWidth: true
        from: 0
        to: 12
        stepSize: 1
        snapMode: Slider.SnapAlways
        value: panel.audio.crossfadeSeconds || 0
        Accessible.name: qsTr("Длительность плавного перехода")
        onMoved: panel.controller.setCrossfadeSeconds(Math.round(value))
    }
    Label {
        visible: panel.desktop && !panel.audio.preloadEnabled
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        color: panel.muted
        text: qsTr("Для плавного перехода нужна предзагрузка.")
    }
    Button {
        Layout.fillWidth: true
        text: panel.expanded ? qsTr("Свернуть эквалайзер") : qsTr("Эквалайзер")
        visible: panel.controller.equalizerAvailable
        onClicked: panel.expanded = !panel.expanded
    }
    CheckBox {
        visible: panel.expanded
        text: qsTr("Включить эквалайзер")
        checked: panel.controller.equalizerEnabled
        onToggled: panel.controller.setEqualizerEnabled(checked)
    }
    Label {
        visible: panel.expanded && (!panel.controller.equalizerPermitted || !!panel.controller.equalizerError)
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        color: panel.muted
        text: panel.controller.equalizerError || qsTr("Эквалайзер применяется к трекам с разрешающей лицензией.")
    }
    ComboBox {
        visible: panel.expanded
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        model: panel.presets
        currentIndex: -1
        displayText: qsTr("Применить пресет")
        Accessible.name: displayText
        onActivated: index => panel.controller.applyEqualizerPreset(index)
    }
    Canvas {
        id: graph
        objectName: "equalizerResponseGraph"
        visible: panel.expanded
        Layout.fillWidth: true
        Layout.preferredHeight: 90
        readonly property var response: panel.controller.equalizerResponse
        onResponseChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            ctx.strokeStyle = panel.muted
            ctx.lineWidth = 1
            ctx.beginPath()
            ctx.moveTo(0, height / 2)
            ctx.lineTo(width, height / 2)
            ctx.stroke()
            ctx.strokeStyle = panel.accent
            ctx.lineWidth = 2
            ctx.beginPath()
            for (let i = 0; i < response.length; ++i) {
                const x = i * width / (response.length - 1)
                const y = height * (0.5 - Math.max(-18, Math.min(18, response[i])) / 36)
                if (i === 0) ctx.moveTo(x, y)
                else ctx.lineTo(x, y)
            }
            ctx.stroke()
        }
    }
    RowLayout {
        visible: panel.expanded
        Layout.fillWidth: true
        spacing: 0
        Repeater {
            model: panel.frequencies
            ColumnLayout {
                id: band
                required property int index
                required property string modelData
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Slider {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredHeight: 108
                    orientation: Qt.Vertical
                    from: -12
                    to: 12
                    stepSize: 1
                    value: panel.controller.equalizerGains[band.index]
                    Accessible.name: band.modelData + " Hz"
                    onMoved: panel.controller.setEqualizerGain(band.index, value)
                }
                Label {
                    Layout.alignment: Qt.AlignHCenter
                    color: panel.ink
                    text: band.modelData
                }
            }
        }
    }
    RowLayout {
        visible: panel.expanded
        Layout.fillWidth: true
        TextField {
            id: presetName
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            maximumLength: 40
            placeholderText: qsTr("Имя пресета")
        }
        Button {
            text: qsTr("Сохранить")
            enabled: presetName.text.trim() !== ""
            onClicked: {
                panel.controller.saveEqualizerPreset(presetName.text)
                presetName.clear()
            }
        }
        Button { text: qsTr("Сбросить"); onClicked: panel.controller.resetEqualizer() }
    }

    Label {
        color: panel.ink
        font.bold: true
        text: qsTr("Таймер сна")
    }
    RowLayout {
        Layout.fillWidth: true
        ComboBox {
            id: sleepMode
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            readonly property var minutes: [15, 30, 45, 60, 90]
            model: minutes.map(value => qsTr("%1 мин").arg(value))
                .concat([qsTr("Своё время"), qsTr("До конца трека")])
            Accessible.name: qsTr("Таймер сна")
        }
        SpinBox {
            id: customTime
            visible: sleepMode.currentIndex === 5
            from: 1
            to: 1440
            value: 20
            editable: true
            Accessible.name: qsTr("Минуты до паузы")
        }
    }
    CheckBox { id: sleepFade; text: qsTr("Плавно убавлять звук"); checked: true }
    RowLayout {
        Layout.fillWidth: true
        Button {
            text: qsTr("Запустить")
            enabled: sleepMode.currentIndex !== 6 || !!panel.audio.current?.urn
            onClicked: panel.controller.startSleepTimer(sleepMode.minutes[sleepMode.currentIndex]
                ?? (sleepMode.currentIndex === 5 ? customTime.value : 0), sleepFade.checked)
        }
        Button {
            visible: !!panel.audio.sleepAtEnd || panel.audio.sleepRemaining >= 0
            text: qsTr("Отмена")
            onClicked: panel.controller.cancelSleepTimer()
        }
        Label {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            color: panel.ink
            text: panel.audio.sleepAtEnd ? qsTr("До конца трека")
                : (panel.audio.sleepRemaining >= 0 ? panel.clock(panel.audio.sleepRemaining) : "")
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        visible: !!panel.audio.current?.urn
        Label { color: panel.ink; font.bold: true; text: qsTr("Участок A–B") }
        RowLayout {
            Layout.fillWidth: true
            TrackProgress {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                enabled: !!panel.audio.seekable
                selectionKey: panel.trackId
                duration: panel.controller.duration
                position: panel.controller.position
                ink: panel.muted
                accent: panel.accent
                onSeekRequested: value => panel.controller.seek(Math.round(value))
            }
            Label { color: panel.muted; text: panel.timestamp(panel.controller.position) }
        }
        Flow {
            Layout.fillWidth: true
            spacing: 6
            Button {
                enabled: !!panel.audio.seekable
                text: panel.audio.loopStart >= 0 ? "A · " + panel.timestamp(panel.audio.loopStart) : qsTr("Поставить A")
                onClicked: panel.controller.setLoopPoint(false)
            }
            Button {
                enabled: !!panel.audio.seekable && panel.audio.loopStart >= 0
                text: panel.audio.loopEnd >= 0 ? "B · " + panel.timestamp(panel.audio.loopEnd) : qsTr("Поставить B")
                onClicked: panel.controller.setLoopPoint(true)
            }
            Button {
                visible: panel.audio.loopStart >= 0
                text: qsTr("Сбросить")
                onClicked: panel.controller.clearLoop()
            }
        }
        Label { color: panel.ink; font.bold: true; text: qsTr("Метки этой сессии") }
        RowLayout {
            Layout.fillWidth: true
            TextField {
                id: momentName
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                maximumLength: 80
                placeholderText: qsTr("Название метки")
            }
            Button {
                text: panel.editedMoment < 0 ? qsTr("Добавить") : qsTr("Сохранить")
                enabled: !!panel.audio.seekable && momentName.text.trim() !== ""
                onClicked: {
                    panel.controller.saveMoment(panel.editedMoment, momentName.text)
                    panel.editMoment(-1, "")
                }
            }
            Button {
                visible: panel.editedMoment >= 0
                text: qsTr("Отмена")
                onClicked: panel.editMoment(-1, "")
            }
        }
        Repeater {
            model: panel.moments
            ColumnLayout {
                id: bookmark
                required property int index
                required property var modelData
                Layout.fillWidth: true
                Button {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: panel.timestamp(bookmark.modelData.position) + " · " + bookmark.modelData.label
                    enabled: !!panel.audio.seekable
                    onClicked: panel.controller.seek(bookmark.modelData.position)
                }
                RowLayout {
                    Button {
                        text: qsTr("Изменить")
                        onClicked: panel.editMoment(bookmark.index, bookmark.modelData.label)
                    }
                    Button {
                        text: qsTr("Удалить")
                        onClicked: {
                            panel.controller.removeMoment(bookmark.index)
                            panel.editMoment(-1, "")
                        }
                    }
                }
            }
        }
    }
    readonly property string trackId: audio.current?.urn || ""
    onTrackIdChanged: {
        editedMoment = -1
        if (momentName) momentName.clear()
    }
}
