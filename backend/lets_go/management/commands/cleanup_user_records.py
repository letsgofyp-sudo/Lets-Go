from __future__ import annotations

import re
from dataclasses import dataclass

from django.core.management.base import BaseCommand
from django.core.exceptions import ValidationError
from django.db import transaction

from lets_go.models import UsersData, EmergencyContact


_EMAIL_DOMAIN_RE = re.compile(
    r"^[^@\s]+@([A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)(?:\.([A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?))*\.[A-Za-z]{2,24}$"
)


def _normalize_spaces(s: str) -> str:
    return (s or "").strip()


def _normalize_upper_nospace(s: str) -> str:
    return (s or "").strip().upper().replace(" ", "")


def _normalize_phone_e164(raw: str) -> str:
    s = (raw or "").strip()
    if not s:
        return ""

    if s.startswith("+"):
        return "+" + re.sub(r"\D", "", s[1:])

    digits = re.sub(r"\D", "", s)
    if not digits:
        return ""

    # Conservative heuristics:
    # - 03XXXXXXXXX -> +92 3XXXXXXXXX
    # - 3XXXXXXXXX (10 digits starting with 3) -> +92...
    # - If 10-15 digits and looks like it already includes country code, prefix '+'
    if len(digits) == 11 and digits.startswith("03"):
        return "+92" + digits[1:]
    if len(digits) == 10 and digits.startswith("3"):
        return "+92" + digits
    if 10 <= len(digits) <= 15 and not digits.startswith("0"):
        return "+" + digits

    return digits


@dataclass
class _RowResult:
    ok: bool
    errors: dict


class Command(BaseCommand):
    help = "Normalize and validate existing user/emergency-contact records under the latest strict validators."

    def add_arguments(self, parser):
        parser.add_argument(
            "--fix",
            action="store_true",
            default=False,
            help="Persist safe normalizations to the database (default is dry-run).",
        )
        parser.add_argument(
            "--limit",
            type=int,
            default=0,
            help="Optional limit for number of users to process (0 = no limit).",
        )

    def handle(self, *args, **options):
        fix = bool(options.get("fix"))
        limit = int(options.get("limit") or 0)

        users_qs = UsersData.objects.all().order_by("id")
        if limit > 0:
            users_qs = users_qs[:limit]

        total = 0
        updated = 0
        invalid = 0

        def normalize_user(u: UsersData) -> None:
            u.username = _normalize_spaces(u.username)
            u.email = _normalize_spaces(u.email).lower()
            u.phone_no = _normalize_phone_e164(u.phone_no)
            u.driving_license_no = _normalize_upper_nospace(u.driving_license_no or "") or None
            u.iban = _normalize_upper_nospace(u.iban or "") or None
            u.accountno = _normalize_upper_nospace(u.accountno or "") or None
            u.bankname = _normalize_spaces(u.bankname or "") or None

        def normalize_ec(ec: EmergencyContact) -> None:
            ec.name = _normalize_spaces(ec.name)
            ec.relation = _normalize_spaces(ec.relation)
            ec.email = _normalize_spaces(ec.email).lower()
            ec.phone_no = _normalize_phone_e164(ec.phone_no)

        def validate_user(u: UsersData) -> _RowResult:
            try:
                u.full_clean()
                if not _EMAIL_DOMAIN_RE.match(u.email or ""):
                    raise ValidationError({"email": ["Enter a valid email address with a valid domain."]})
                return _RowResult(ok=True, errors={})
            except ValidationError as e:
                msg = getattr(e, "message_dict", None) or {"__all__": [str(e)]}
                return _RowResult(ok=False, errors=msg)

        def validate_ec(ec: EmergencyContact) -> _RowResult:
            try:
                ec.full_clean()
                if not _EMAIL_DOMAIN_RE.match(ec.email or ""):
                    raise ValidationError({"email": ["Enter a valid email address with a valid domain."]})
                return _RowResult(ok=True, errors={})
            except ValidationError as e:
                msg = getattr(e, "message_dict", None) or {"__all__": [str(e)]}
                return _RowResult(ok=False, errors=msg)

        with transaction.atomic():
            for u in users_qs:
                total += 1
                before = {
                    "username": u.username,
                    "email": u.email,
                    "phone_no": u.phone_no,
                    "driving_license_no": u.driving_license_no,
                    "iban": u.iban,
                    "accountno": u.accountno,
                    "bankname": u.bankname,
                }

                normalize_user(u)

                res = validate_user(u)
                if not res.ok:
                    invalid += 1
                    self.stdout.write(self.style.ERROR(f"[UsersData id={u.id}] invalid: {res.errors}"))
                else:
                    after = {
                        "username": u.username,
                        "email": u.email,
                        "phone_no": u.phone_no,
                        "driving_license_no": u.driving_license_no,
                        "iban": u.iban,
                        "accountno": u.accountno,
                        "bankname": u.bankname,
                    }
                    changed = before != after
                    if changed:
                        updated += 1
                        self.stdout.write(self.style.WARNING(f"[UsersData id={u.id}] normalized: {before} -> {after}"))
                        if fix:
                            u.save(update_fields=list(after.keys()))

                try:
                    ec = EmergencyContact.objects.get(user=u)
                except EmergencyContact.DoesNotExist:
                    continue

                before_ec = {
                    "name": ec.name,
                    "relation": ec.relation,
                    "email": ec.email,
                    "phone_no": ec.phone_no,
                }

                normalize_ec(ec)
                res_ec = validate_ec(ec)
                if not res_ec.ok:
                    invalid += 1
                    self.stdout.write(self.style.ERROR(f"[EmergencyContact user_id={u.id}] invalid: {res_ec.errors}"))
                else:
                    after_ec = {
                        "name": ec.name,
                        "relation": ec.relation,
                        "email": ec.email,
                        "phone_no": ec.phone_no,
                    }
                    changed_ec = before_ec != after_ec
                    if changed_ec:
                        updated += 1
                        self.stdout.write(self.style.WARNING(f"[EmergencyContact user_id={u.id}] normalized: {before_ec} -> {after_ec}"))
                        if fix:
                            ec.save(update_fields=list(after_ec.keys()))

            if not fix:
                transaction.set_rollback(True)

        self.stdout.write(
            self.style.SUCCESS(
                f"Done. processed={total} normalized={updated} invalid={invalid} mode={'fix' if fix else 'dry-run'}"
            )
        )
