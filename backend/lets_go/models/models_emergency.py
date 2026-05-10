from django.db import models
from django.core.validators import RegexValidator
from django.core.exceptions import ValidationError

from .models_userdata import UsersData


class EmergencyContact(models.Model):
    user = models.OneToOneField(
        UsersData,
        on_delete=models.CASCADE,
        related_name='emergency_contact',
    )
    name = models.CharField(max_length=100)
    relation = models.CharField(max_length=50)
    email = models.EmailField()
    phone_no = models.CharField(
        max_length=16,
        validators=[
            RegexValidator(
                regex=r"^\d{10,15}$",
                message="Emergency phone must be 10-15 digits (no country prefix)",
            )
        ],
    )

    def clean(self):
        import re

        if self.phone_no:
            raw = str(self.phone_no).strip().replace(' ', '')
            if raw.startswith('+'):
                digits = raw[1:]
            else:
                digits = raw
            if not digits.isdigit() or not (10 <= len(digits) <= 15):
                raise ValidationError({'phone_no': 'Emergency phone must be 10-15 digits (no country prefix)'})
            # Legacy-compatible storage: digits only
            self.phone_no = digits

        if self.email:
            email = self.email.strip()
            self.email = email
            if not re.match(
                r"^[^@\s]+@([A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)(?:\.([A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?))*\.[A-Za-z]{2,24}$",
                email,
            ):
                raise ValidationError({'email': 'Enter a valid email address with a valid domain.'})

    def __str__(self):
        return f"{self.name} ({self.relation}) for {self.user.name}"
