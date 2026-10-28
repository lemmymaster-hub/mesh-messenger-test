import 'dart:convert';

import 'planner_engine.dart';

/// Empty operational input: no invented radio, terrain or team capabilities.
Json emptyScenario() => {
  'schemaVersion': 1,
  'mission': 'Nova NRN akcija',
  'hq': {
    'id': 'stab',
    'lat': null,
    'lng': null,
    'elevationM': null,
    'antennaM': 2,
  },
  'incident': {
    'id': 'incident',
    'lat': null,
    'lng': null,
    'elevationM': null,
    'antennaM': 1.5,
  },
  'stations': <Json>[], 'airSites': <Json>[], 'profiles': <Json>[],
  'stationLimit': 0,
  // Deliberately incomplete: commander must supply the actual equipment profile.
  'radio': {
    'frequencyMHz': null,
    'txDbm': null,
    'sensitivityDbm': null,
    'gainDbi': null,
    'lossDb': null,
    'requiredMarginDb': null,
  },
  'drone': {
    'minAglM': 20,
    'maxAglM': 100,
    'stepM': 10,
    'enduranceMinutes': 0,
    'transitMinutes': 0,
    'reserveMinutes': 0,
    'requiredMinutes': 10,
    'conditionsConfirmed': false,
  },
  'teams': <Json>[], 'tasks': <Json>[],
  'reportTimeoutMinutes': 10, 'batteryAlertPercent': 25,
};

/// Synthetic classroom exercise, never actual terrain or equipment settings.
Json demoScenario() =>
    PlannerEngine.object(jsonDecode(jsonEncode(_demoData())));

Json _demoData() => {
  ...emptyScenario(),
  'mission': 'DEMO — sintetička vježba, nije stvarni teren',
  'hq': {
    'id': 'stab',
    'lat': 43.85,
    'lng': 18.4,
    'elevationM': 600,
    'antennaM': 5,
  },
  'incident': {
    'id': 'incident',
    'lat': 43.85,
    'lng': 18.42,
    'elevationM': 600,
    'antennaM': 2,
  },
  'stations': [
    {
      'id': 'stanica-1',
      'lat': 43.851,
      'lng': 18.41,
      'elevationM': 650,
      'antennaM': 5,
      'accessible': true,
    },
  ],
  'airSites': [
    {
      'id': 'relej-1',
      'lat': 43.85,
      'lng': 18.41,
      'elevationM': 620,
      'antennaM': 0,
      'accessible': true,
    },
  ],
  'profiles': [
    {
      'from': 'stab',
      'to': 'incident',
      'source': 'DEMO sintetički profil',
      'samples': [600, 640, 600],
    },
    {
      'from': 'stab',
      'to': 'stanica-1',
      'source': 'DEMO sintetički profil',
      'samples': [600, 610, 650],
    },
    {
      'from': 'stanica-1',
      'to': 'incident',
      'source': 'DEMO sintetički profil',
      'samples': [650, 610, 600],
    },
    {
      'from': 'stab',
      'to': 'relej-1',
      'source': 'DEMO sintetički profil',
      'samples': [600, 610, 620],
    },
    {
      'from': 'relej-1',
      'to': 'incident',
      'source': 'DEMO sintetički profil',
      'samples': [620, 610, 600],
    },
  ],
  'stationLimit': 1,
  'radio': {
    'frequencyMHz': 868,
    'txDbm': 14,
    'sensitivityDbm': -120,
    'gainDbi': 2,
    'lossDb': 3,
    'requiredMarginDb': 15,
  },
  'drone': {
    'minAglM': 20,
    'maxAglM': 100,
    'stepM': 10,
    'enduranceMinutes': 35,
    'transitMinutes': 10,
    'reserveMinutes': 10,
    'requiredMinutes': 10,
    'conditionsConfirmed': true,
  },
  'teams': [
    {
      'id': 'alfa',
      'name': 'Tim Alfa',
      'lat': 43.85,
      'lng': 18.4,
      'skills': ['prva_pomoc'],
      'available': true,
    },
    {
      'id': 'bravo',
      'name': 'Tim Bravo',
      'lat': 43.851,
      'lng': 18.4,
      'skills': ['radio'],
      'available': true,
    },
  ],
  'tasks': [
    {
      'id': 'pomoc',
      'name': 'Pristup i prva pomoć',
      'lat': 43.85,
      'lng': 18.42,
      'requires': ['prva_pomoc'],
      'priority': 5,
      'routeConfirmed': true,
    },
    {
      'id': 'radio',
      'name': 'Postavljanje stanice',
      'lat': 43.851,
      'lng': 18.41,
      'requires': ['radio'],
      'priority': 4,
      'routeConfirmed': true,
    },
  ],
};
