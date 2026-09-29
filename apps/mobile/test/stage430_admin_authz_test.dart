// Stage 4.30 — ADMIN-3 portal: permission-driven navigation gating.
//
// The shell catalogs sections in `adminSectionsFor`; every section must be
// reachable only when the session advertises the matching backend permission
// code. These tests pin that mapping so a future rebrand can't secretly widen
// the portal. Roles alone never open a section — only permission codes do.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sicklers_warriors/features/admin/domain/admin_authz.dart';

void main() {
  group('adminSectionsFor gating', () {
    test('no permissions render no sections', () {
      final sections = adminSectionsFor(permissions: const [], roles: const []);
      expect(sections, isEmpty);
    });

    test('roles alone never open a section', () {
      final sections = adminSectionsFor(
        permissions: const [],
        roles: const ['SUPER_ADMIN'],
      );
      expect(sections, isEmpty);
    });

    test('SUPER_ADMIN grant matrix renders the full catalog in order', () {
      final sections = adminSectionsFor(
        permissions: const [
          AdminPermissions.analyticsView,
          AdminPermissions.usersManage,
          AdminPermissions.doctorsVerify,
          AdminPermissions.facilitiesVerify,
          AdminPermissions.bloodVerify,
          AdminPermissions.campaignsVerify,
          AdminPermissions.rolesView,
          AdminPermissions.educationReview,
          AdminPermissions.communityModerate,
          AdminPermissions.donationsView,
          AdminPermissions.broadcast,
          AdminPermissions.auditView,
          AdminPermissions.auditAdminRead,
        ],
        roles: const ['SUPER_ADMIN'],
      );
      expect(
        sections.map((s) => s.label),
        [
          'Dashboard',
          'Users',
          'Doctors',
          'Organizations',
          'Blood Verification',
          'Campaigns',
          'Roles & Permissions',
          'Content Review',
          'Moderation',
          'Finance',
          'Broadcast',
          'Audit Logs',
          'Security Events',
          'Analytics',
          'AI Monitoring',
        ],
      );
    });

    test('a minimized staff admin sees only their permitted sections', () {
      final sections = adminSectionsFor(
        permissions: const [
          AdminPermissions.usersManage,
          AdminPermissions.bloodVerify,
        ],
        roles: const ['ADMIN'],
      );
      expect(sections.map((s) => s.label), ['Users', 'Blood Verification']);
    });

    test('analytics permission surfaces Dashboard and Analytics, not others', () {
      final sections = adminSectionsFor(
        permissions: const [AdminPermissions.analyticsView],
        roles: const [],
      );
      expect(sections.map((s) => s.label), ['Dashboard', 'Analytics']);
    });

    test('audit reader sees audit surface and AI monitoring only', () {
      final sections = adminSectionsFor(
        permissions: const [AdminPermissions.auditAdminRead],
        roles: const [],
      );
      expect(sections.map((s) => s.label), ['Security Events', 'AI Monitoring']);
    });

    test('users manager does not get roles management for free', () {
      final sections = adminSectionsFor(
        permissions: const [AdminPermissions.usersManage],
        roles: const ['SUPER_ADMIN'],
      );
      expect(sections.map((s) => s.label), ['Users']);
    });

    test('every grant code maps to exactly one canonical section', () {
      const granular = {
        AdminPermissions.usersManage: 'Users',
        AdminPermissions.doctorsVerify: 'Doctors',
        AdminPermissions.facilitiesVerify: 'Organizations',
        AdminPermissions.bloodVerify: 'Blood Verification',
        AdminPermissions.campaignsVerify: 'Campaigns',
        AdminPermissions.rolesView: 'Roles & Permissions',
        AdminPermissions.educationReview: 'Content Review',
        AdminPermissions.communityModerate: 'Moderation',
        AdminPermissions.donationsView: 'Finance',
        AdminPermissions.broadcast: 'Broadcast',
        AdminPermissions.auditView: 'Audit Logs',
      };
      granular.forEach((code, label) {
        final sections = adminSectionsFor(
          permissions: [code],
          roles: const [],
        );
        expect(sections.map((s) => s.label), [label], reason: 'for $code');
        expect(sections.single.permissions, contains(code));
      });
    });
  });

  group('AdminSection shape', () {
    test('sections carry icons and their gating codes', () {
      final sections = adminSectionsFor(
        permissions: const [AdminPermissions.usersManage],
        roles: const [],
      );
      final section = sections.single;
      expect(section.icon, isA<IconData>());
      expect(section.selectedIcon, isA<IconData>());
      expect(section.permissions, isNotNull);
    });
  });
}