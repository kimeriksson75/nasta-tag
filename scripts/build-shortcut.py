#!/usr/bin/env python3
"""Bygger genvägen till Apple Watch: python3 scripts/build-shortcut.py ut.shortcut

Stationerna frågas efter när genvägen läggs till, så filen innehåller inga egna uppgifter.
"""
import plistlib
import sys
import uuid

API_URL = 'https://nasta-tag-production.up.railway.app/api/next'
PLACEHOLDER = '￼'


def output(uuid_, name):
    return {'Type': 'ActionOutput', 'OutputUUID': uuid_, 'OutputName': name}


def token(variable):
    return {
        'Value': {'string': PLACEHOLDER, 'attachmentsByRange': {'{0, 1}': variable}},
        'WFSerializationType': 'WFTextTokenString',
    }


def text(value):
    return {'Value': {'string': value}, 'WFSerializationType': 'WFTextTokenString'}


def attachment(variable):
    return {'Value': variable, 'WFSerializationType': 'WFTextTokenAttachment'}


def field(key, value):
    return {'WFItemType': 0, 'WFKey': text(key), 'WFValue': value}


def action(identifier, **parameters):
    return {'WFWorkflowActionIdentifier': f'is.workflow.actions.{identifier}', 'WFWorkflowActionParameters': parameters}


def question(index, prompt):
    return {
        'ActionIndex': index,
        'Category': 'Parameter',
        'DefaultValue': '',
        'ParameterKey': 'WFTextActionText',
        'Text': prompt,
    }


def build():
    home, work, location, lat, lon, answer = (str(uuid.uuid4()).upper() for _ in range(6))
    place = output(location, 'Current Location')
    return {
        'WFWorkflowClientVersion': '2607.0.5',
        'WFWorkflowMinimumClientVersion': 900,
        'WFWorkflowMinimumClientVersionString': '900',
        'WFWorkflowHasOutputFallback': False,
        'WFWorkflowHasShortcutInputVariables': False,
        'WFWorkflowIcon': {'WFWorkflowIconStartColor': 4282601983, 'WFWorkflowIconGlyphNumber': 59511},
        'WFWorkflowImportQuestions': [
            question(0, 'Vilken tunnelbanestation bor du vid?'),
            question(1, 'Vilken tunnelbanestation jobbar du vid?'),
        ],
        'WFWorkflowInputContentItemClasses': [],
        'WFWorkflowOutputContentItemClasses': [],
        'WFWorkflowTypes': ['Watch'],
        'WFWorkflowActions': [
            action('gettext', UUID=home, WFTextActionText=''),
            action('gettext', UUID=work, WFTextActionText=''),
            action('getcurrentlocation', UUID=location),
            action('properties.locations', UUID=lat, WFContentItemPropertyName='Latitude', WFInput=attachment(place)),
            action('properties.locations', UUID=lon, WFContentItemPropertyName='Longitude', WFInput=attachment(place)),
            action(
                'downloadurl',
                UUID=answer,
                ShowHeaders=True,
                WFURL=API_URL,
                WFHTTPMethod='POST',
                WFHTTPBodyType='JSON',
                WFJSONValues={
                    'Value': {'WFDictionaryFieldValueItems': [
                        field('lat', token(output(lat, 'Latitude'))),
                        field('lon', token(output(lon, 'Longitude'))),
                        field('home', token(output(home, 'Text'))),
                        field('work', token(output(work, 'Text'))),
                    ]},
                    'WFSerializationType': 'WFDictionaryFieldValue',
                },
            ),
            action('showresult', Text=token(output(answer, 'Contents of URL'))),
        ],
    }


if __name__ == '__main__':
    with open(sys.argv[1], 'wb') as file:
        plistlib.dump(build(), file, fmt=plistlib.FMT_BINARY)
