//
//  AudioInjectorOptions.cpp
//  libraries/audio/src
//
//  Created by Stephen Birarda on 1/2/2014.
//  Copyright 2014 High Fidelity, Inc.
//
//  Distributed under the Apache License, Version 2.0.
//  See the accompanying file LICENSE or http://www.apache.org/licenses/LICENSE-2.0.html
//

#include "AudioInjectorOptions.h"

#include <QScriptValueIterator>

#include <RegisteredMetaTypes.h>

#include "AudioLogging.h"

AudioInjectorOptions::AudioInjectorOptions() :
    position(0.0f, 0.0f, 0.0f),
    volume(1.0f),
    loop(false),
    orientation(glm::vec3(0.0f, 0.0f, 0.0f)),
    stereo(false),
    ambisonic(false),
    ignorePenumbra(false),
    localOnly(false),
    secondOffset(0.0f),
    pitch(1.0f)
{

}

QScriptValue injectorOptionsToScriptValue(QScriptEngine* engine, const AudioInjectorOptions& injectorOptions) {
    QScriptValue obj = engine->newObject();
    obj.setProperty("position", vec3toScriptValue(engine, injectorOptions.position));
    obj.setProperty("volume", injectorOptions.volume);
    obj.setProperty("loop", injectorOptions.loop);
    obj.setProperty("orientation", quatToScriptValue(engine, injectorOptions.orientation));
    obj.setProperty("ignorePenumbra", injectorOptions.ignorePenumbra);
    obj.setProperty("localOnly", injectorOptions.localOnly);
    obj.setProperty("secondOffset", injectorOptions.secondOffset);
    obj.setProperty("pitch", injectorOptions.pitch);
    return obj;
}

/**jsdoc
 * Configures how an audio injector plays its audio.
 * @typedef {object} AudioInjector.AudioInjectorOptions
 * @property {Vec3} position=Vec3.ZERO - The position in the domain to play the sound.
 * @property {Quat} orientation=Quat.IDENTITY - The orientation in the domain to play the sound in.
 * @property {number} volume=1.0 - Playback volume, between <code>0.0</code> and <code>1.0</code>.
 * @property {number} pitch=1.0 - Alter the pitch of the sound, within +/- 2 octaves. The value is the relative sample rate to 
 *     resample the sound at, range <code>0.0625</code> &ndash; <code>16.0</code>. A value of <code>0.0625</code> lowers the 
 *     pitch by 2 octaves; <code>1.0</code> is no change in pitch; <code>16.0</code> raises the pitch by 2 octaves.
 * @property {boolean} loop=false - If <code>true</code>, the sound is played repeatedly until playback is stopped.
 * @property {number} secondOffset=0 - Starts playback from a specified time (seconds) within the sound file, &ge; 
 *     <code>0</code>.
 * @property {boolean} localOnly=false - IF <code>true</code>, the sound is played back locally on the client rather than to
 *     others via the audio mixer.
 * @property {boolean} ignorePenumbra=false - <strong>Deprecated:</strong> This property is deprecated and will be
 *     removed.
 */
void injectorOptionsFromScriptValue(const QScriptValue& object, AudioInjectorOptions& injectorOptions) {
    if (!object.isObject()) {
        qWarning() << "Audio injector options is not an object.";
        return;
    }

    QScriptValueIterator it(object);
    while (it.hasNext()) {
        it.next();

        if (it.name() == "position") {
            vec3FromScriptValue(object.property("position"), injectorOptions.position);
        } else if (it.name() == "orientation") {
            quatFromScriptValue(object.property("orientation"), injectorOptions.orientation);
        } else if (it.name() == "volume") {
            if (it.value().isNumber()) {
                injectorOptions.volume = it.value().toNumber();
            } else {
                qCWarning(audio) << "Audio injector options: volume is not a number";
            }
        } else if (it.name() == "loop") {
            if (it.value().isBool()) {
                injectorOptions.loop = it.value().toBool();
            } else {
                qCWarning(audio) << "Audio injector options: loop is not a boolean";
            }
        } else if (it.name() == "ignorePenumbra") {
            if (it.value().isBool()) {
                injectorOptions.ignorePenumbra = it.value().toBool();
            } else {
                qCWarning(audio) << "Audio injector options: ignorePenumbra is not a boolean";
            }
        } else if (it.name() == "localOnly") {
            if (it.value().isBool()) {
                injectorOptions.localOnly = it.value().toBool();
            } else {
                qCWarning(audio) << "Audio injector options: localOnly is not a boolean";
            }
        } else if (it.name() == "secondOffset") {
            if (it.value().isNumber()) {
                injectorOptions.secondOffset = it.value().toNumber();
            } else {
                qCWarning(audio) << "Audio injector options: secondOffset is not a number";
            }
        } else if (it.name() == "pitch") {
            if (it.value().isNumber()) {
                injectorOptions.pitch = it.value().toNumber();
            } else {
                qCWarning(audio) << "Audio injector options: pitch is not a number";
            }
        } else {
            qCWarning(audio) << "Unknown audio injector option:" << it.name();
        }
    }
}
