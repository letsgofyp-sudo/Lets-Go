from django.db import models
from django.core.validators import RegexValidator, MinLengthValidator
from django.core.exceptions import ValidationError
from django.utils.translation import gettext_lazy as _


_DL_NO_VALIDATOR = RegexValidator(
    regex=r"^[A-Z0-9][A-Z0-9\-/]{4,19}$",
    message="Driving license number must be 5-20 characters and contain only letters, digits, '-' or '/'.",
)

_ACCOUNT_NO_VALIDATOR = RegexValidator(
    regex=r"^\d{10,20}$",
    message="Account number must be 10-20 digits.",
)

_BANK_NAME_VALIDATOR = RegexValidator(
    regex=r"^[A-Za-z][A-Za-z .&\-]{1,118}[A-Za-z.]$",
    message="Bank name must be 2-120 characters and contain only letters, spaces, '.', '&' or '-'.",
)

_PK_IBAN_VALIDATOR = RegexValidator(
    regex=r"^PK\d{2}[A-Z]{4}\d{16}$",
    message="IBAN must be a valid Pakistan IBAN (24 chars), e.g. PK36SCBL0000001123456702.",
)

_USERNAME_VALIDATOR = RegexValidator(
    regex=r"^(?=.*[A-Za-z])[A-Za-z0-9._]{3,32}$",
    message="Username must be 3-32 chars, contain at least one letter, and only use letters, numbers, '.' or '_'.",
)


class UsernameRegistry(models.Model):
    """Dedicated table for tracking reserved usernames.

    This is used during signup to ensure a username is unique *before* a
    UsersData record exists. The UsersData.username field can still remain
    unique at the database level as the final source of truth.
    """
    username = models.CharField(max_length=100, unique=True, validators=[_USERNAME_VALIDATOR])
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return self.username


class UsersData(models.Model):
    name = models.CharField(max_length=100)
    username = models.CharField(max_length=100, unique=True, validators=[_USERNAME_VALIDATOR])
    email = models.EmailField(unique=True)
    password = models.CharField(
        max_length=128,
        validators=[
            MinLengthValidator(8),
        ]
    )
    address = models.TextField()
    phone_no = models.CharField(
        max_length=16,  # allow for + and up to 15 digits
        unique=True,
        validators=[
            RegexValidator(
                regex=r"^\+\d{10,15}$",
                message="Phone number must be in international format, e.g. +923001234567"
            )
        ]
    )
    cnic_no = models.CharField(
        max_length=15,
        unique=True,
        validators=[
            RegexValidator(
                regex=r"^\d{5}-\d{7}-\d{1}$",
                message="CNIC must be in the format 36603-0269853-9"
            )
        ]
    )
    gender = models.CharField(
        max_length=10,
        choices=[('male', 'Male'), ('female', 'Female')]
    )
    driving_license_no = models.CharField(
        max_length=20,
        null=True,
        blank=True,
        unique=True,
        validators=[_DL_NO_VALIDATOR],
    )
    accountno = models.CharField(
        max_length=20,
        null=True,
        blank=True,
        validators=[_ACCOUNT_NO_VALIDATOR],
    )
    bankname = models.CharField(
        max_length=120,
        null=True,
        blank=True,
        validators=[_BANK_NAME_VALIDATOR],
    )
    iban = models.CharField(
        max_length=34,
        null=True,
        blank=True,
        validators=[_PK_IBAN_VALIDATOR],
    )
    profile_photo_url = models.URLField(null=True, blank=True)
    live_photo_url = models.URLField(null=True, blank=True)
    cnic_front_image_url = models.URLField(null=True, blank=True)
    cnic_back_image_url = models.URLField(null=True, blank=True)
    status = models.CharField(
        max_length=10,
        default='PENDING',
        choices=[
            ('PENDING', 'Pending'),
            ('VERIFIED', 'Verified'),
            ('REJECTED', 'Rejected'),
            ('BANNED', 'Banned'),
        ]
    )
    rejection_reason = models.TextField(null=True, blank=True)
    driving_license_front_url = models.URLField(null=True, blank=True)
    driving_license_back_url = models.URLField(null=True, blank=True)
    accountqr_url = models.URLField(null=True, blank=True)
    driver_rating = models.DecimalField(max_digits=3, decimal_places=2, null=True, blank=True)
    passenger_rating = models.DecimalField(max_digits=3, decimal_places=2, null=True, blank=True)
    fcm_token = models.TextField(null=True, blank=True, help_text='Firebase Cloud Messaging token for push notifications')
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def clean(self):
        # Password complexity
        import re

        if self.username:
            self.username = self.username.strip()

        if self.email:
            email = self.email.strip()
            self.email = email
            # Extra strictness beyond EmailField: validate domain labels and TLD.
            # Blocks obviously invalid/random domains like "a@b", "a@domain", "a@-x.com", etc.
            if not re.match(r"^[^@\s]+@([A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)(?:\.([A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?))*\.[A-Za-z]{2,24}$", email):
                raise ValidationError({'email': _('Enter a valid email address with a valid domain.')})

        if self.driving_license_no is not None:
            dl = str(self.driving_license_no).strip().upper().replace(' ', '')
            self.driving_license_no = dl or None
        if self.accountno:
            self.accountno = self.accountno.strip().replace(' ', '')
        if self.iban:
            self.iban = self.iban.strip().upper().replace(' ', '')
        if self.bankname:
            self.bankname = self.bankname.strip()

        if self.password:
            # Note: signup hashes passwords before saving. Avoid validating complexity on already-hashed values.
            pw = str(self.password)
            looks_hashed = pw.startswith('pbkdf2_') or pw.startswith('argon2$') or pw.startswith('bcrypt$')
            if not looks_hashed:
                if not re.search(r"[A-Z]", pw):
                    raise ValidationError({'password': _('Password must contain at least one uppercase letter.')})
                if not re.search(r"[a-z]", pw):
                    raise ValidationError({'password': _('Password must contain at least one lowercase letter.')})
                if not re.search(r"\d", pw):
                    raise ValidationError({'password': _('Password must contain at least one digit.')})
                if not re.search(r"[!@#$%^&*()_+\-=\[\]{};':\"\\|,.<>\/?]", pw):
                    raise ValidationError({'password': _('Password must contain at least one special character.')})

        # If driving_license_no is provided, both images are required
        if self.driving_license_no:
            if not self.driving_license_front_url or not self.driving_license_back_url:
                errors = {}
                if not self.driving_license_front_url:
                    errors['driving_license_front_url'] = _('Driving license front image is required when providing license number.')
                if not self.driving_license_back_url:
                    errors['driving_license_back_url'] = _('Driving license back image is required when providing license number.')
                raise ValidationError(errors)

        # If either accountno or iban is provided, bankname is required
        if (self.accountno or self.iban) and not self.bankname:
            raise ValidationError({'bankname': _('Bank name is required when providing bank account details.')})

        if not self.profile_photo_url:
            raise ValidationError({'profile_photo_url': _('Profile photo is required.')})
        if not self.live_photo_url:
            raise ValidationError({'live_photo_url': _('Live photo is required.')})
        if not self.cnic_front_image_url:
            raise ValidationError({'cnic_front_image_url': _('CNIC front image is required.')})
        if not self.cnic_back_image_url:
            raise ValidationError({'cnic_back_image_url': _('CNIC back image is required.')})

    def __str__(self):
        return self.name
