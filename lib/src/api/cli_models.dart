class CliStatusBody {
  final String message;
  final String version;

  CliStatusBody({required this.message, required this.version});

  factory CliStatusBody.fromJson(Map<String, dynamic> json) => CliStatusBody(
        message: json['message'] as String? ?? '',
        version: json['version'] as String? ?? '',
      );
}

class CliOrganisationBody {
  final String organisationName;
  final String obfuscatedId;

  CliOrganisationBody(
      {required this.organisationName, required this.obfuscatedId});

  factory CliOrganisationBody.fromJson(Map<String, dynamic> json) =>
      CliOrganisationBody(
        organisationName: json['organisationName'] as String? ?? '',
        obfuscatedId: json['obfuscatedId'] as String? ?? '',
      );
}

class CliTestOrganisationBody {
  final String organisationName;
  final String obfuscatedId;
  final String operatorEmail;
  final String plan;
  final String onepubToken;

  CliTestOrganisationBody({
    required this.organisationName,
    required this.obfuscatedId,
    required this.operatorEmail,
    required this.plan,
    required this.onepubToken,
  });

  factory CliTestOrganisationBody.fromJson(Map<String, dynamic> json) =>
      CliTestOrganisationBody(
        organisationName: json['organisationName'] as String? ?? '',
        obfuscatedId: json['obfuscatedId'] as String? ?? '',
        operatorEmail: json['operatorEmail'] as String? ?? '',
        plan: json['plan'] as String? ?? '',
        onepubToken: json['onepubToken'] as String? ?? '',
      );
}

class CliMemberBody {
  final String email;
  final String firstname;
  final String lastname;
  final Set<String> roles;
  final String organisationName;
  final String obfuscateOrganisationId;

  CliMemberBody({
    required this.email,
    required this.firstname,
    required this.lastname,
    required this.roles,
    required this.organisationName,
    required this.obfuscateOrganisationId,
  });

  factory CliMemberBody.fromJson(Map<String, dynamic> json) => CliMemberBody(
        email: json['email'] as String? ?? '',
        firstname: json['firstname'] as String? ?? '',
        lastname: json['lastname'] as String? ?? '',
        roles: _stringSet(json['roles']),
        organisationName: json['organisationName'] as String? ?? '',
        obfuscateOrganisationId:
            json['obfuscateOrganisationId'] as String? ?? '',
      );
}

class CliExportTokenBody {
  final String onepubToken;

  CliExportTokenBody({required this.onepubToken});

  factory CliExportTokenBody.fromJson(Map<String, dynamic> json) =>
      CliExportTokenBody(
        onepubToken: json['onepubToken'] as String? ?? '',
      );
}

class CliAuthBody {
  final String status;
  final int pollInterval;
  final String message;
  final String onePubToken;
  final bool firstLogin;
  final String operatorEmail;
  final String organisationName;
  final String obfuscatedOrganisationId;

  CliAuthBody({
    required this.status,
    required this.pollInterval,
    required this.message,
    required this.onePubToken,
    required this.firstLogin,
    required this.operatorEmail,
    required this.organisationName,
    required this.obfuscatedOrganisationId,
  });

  factory CliAuthBody.fromJson(Map<String, dynamic> json) => CliAuthBody(
        status: json['status'] as String? ?? '',
        pollInterval: json['pollInterval'] as int? ?? 0,
        message: json['message'] as String? ?? '',
        onePubToken: json['onePubToken'] as String? ?? '',
        firstLogin: json['firstLogin'] as bool? ?? false,
        operatorEmail: json['operatorEmail'] as String? ?? '',
        organisationName: json['organisationName'] as String? ?? '',
        obfuscatedOrganisationId:
            json['obfuscatedOrganisationId'] as String? ?? '',
      );
}

class CliTeamInfo {
  final int? id;
  final String name;
  final bool everyoneTeam;
  final bool leader;

  CliTeamInfo({
    required this.id,
    required this.name,
    required this.everyoneTeam,
    required this.leader,
  });

  factory CliTeamInfo.fromJson(Map<String, dynamic> json) => CliTeamInfo(
        id: json['id'] as int?,
        name: json['name'] as String? ?? '',
        everyoneTeam: json['everyoneTeam'] as bool? ?? false,
        leader: json['leader'] as bool? ?? false,
      );
}

class CliTeamListBody {
  final List<CliTeamInfo> teams;

  CliTeamListBody({required this.teams});

  factory CliTeamListBody.fromJson(Map<String, dynamic> json) =>
      CliTeamListBody(
        teams: _teamList(json['teams']),
      );
}

class CliWhoAmIBody {
  final String email;
  final String firstname;
  final String lastname;
  final Set<String> roles;
  final String organisationName;
  final String obfuscatedOrganisationId;

  CliWhoAmIBody({
    required this.email,
    required this.firstname,
    required this.lastname,
    required this.roles,
    required this.organisationName,
    required this.obfuscatedOrganisationId,
  });

  factory CliWhoAmIBody.fromJson(Map<String, dynamic> json) => CliWhoAmIBody(
        email: json['email'] as String? ?? '',
        firstname: json['firstname'] as String? ?? '',
        lastname: json['lastname'] as String? ?? '',
        roles: _stringSet(json['roles']),
        organisationName: json['organisationName'] as String? ?? '',
        obfuscatedOrganisationId:
            json['obfuscatedOrganisationId'] as String? ?? '',
      );
}

Set<String> _stringSet(Object? value) {
  final list = value as List? ?? const <dynamic>[];
  final set = <String>{};
  for (final entry in list) {
    if (entry is String) {
      set.add(entry);
    }
  }
  return set;
}

List<CliTeamInfo> _teamList(Object? value) {
  final list = value as List? ?? const <dynamic>[];
  final teams = <CliTeamInfo>[];
  for (final entry in list) {
    if (entry is Map<String, dynamic>) {
      teams.add(CliTeamInfo.fromJson(entry));
    } else if (entry is Map<String, Object?>) {
      teams.add(CliTeamInfo.fromJson(Map<String, dynamic>.from(entry)));
    }
  }
  return teams;
}
