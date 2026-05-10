(function () {
  function normalizeUsername(v) {
    return (v || '').trim();
  }

  const strictEmailRe = /^[^@\s]+@([A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)(?:\.([A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?))*\.[A-Za-z]{2,24}$/;

  const dialCodes = [
    { name: 'Afghanistan', code: '+93' },
    { name: 'Albania', code: '+355' },
    { name: 'Algeria', code: '+213' },
    { name: 'American Samoa', code: '+1-684' },
    { name: 'Andorra', code: '+376' },
    { name: 'Angola', code: '+244' },
    { name: 'Anguilla', code: '+1-264' },
    { name: 'Antigua and Barbuda', code: '+1-268' },
    { name: 'Argentina', code: '+54' },
    { name: 'Armenia', code: '+374' },
    { name: 'Aruba', code: '+297' },
    { name: 'Australia', code: '+61' },
    { name: 'Austria', code: '+43' },
    { name: 'Azerbaijan', code: '+994' },
    { name: 'Bahamas', code: '+1-242' },
    { name: 'Bahrain', code: '+973' },
    { name: 'Bangladesh', code: '+880' },
    { name: 'Barbados', code: '+1-246' },
    { name: 'Belarus', code: '+375' },
    { name: 'Belgium', code: '+32' },
    { name: 'Belize', code: '+501' },
    { name: 'Benin', code: '+229' },
    { name: 'Bermuda', code: '+1-441' },
    { name: 'Bhutan', code: '+975' },
    { name: 'Bolivia', code: '+591' },
    { name: 'Bosnia and Herzegovina', code: '+387' },
    { name: 'Botswana', code: '+267' },
    { name: 'Brazil', code: '+55' },
    { name: 'British Virgin Islands', code: '+1-284' },
    { name: 'Brunei', code: '+673' },
    { name: 'Bulgaria', code: '+359' },
    { name: 'Burkina Faso', code: '+226' },
    { name: 'Burundi', code: '+257' },
    { name: 'Cambodia', code: '+855' },
    { name: 'Cameroon', code: '+237' },
    { name: 'Canada', code: '+1' },
    { name: 'Cape Verde', code: '+238' },
    { name: 'Cayman Islands', code: '+1-345' },
    { name: 'Central African Republic', code: '+236' },
    { name: 'Chad', code: '+235' },
    { name: 'Chile', code: '+56' },
    { name: 'China', code: '+86' },
    { name: 'Colombia', code: '+57' },
    { name: 'Comoros', code: '+269' },
    { name: 'Congo (DRC)', code: '+243' },
    { name: 'Congo (Republic)', code: '+242' },
    { name: 'Cook Islands', code: '+682' },
    { name: 'Costa Rica', code: '+506' },
    { name: 'Croatia', code: '+385' },
    { name: 'Cuba', code: '+53' },
    { name: 'Curaçao', code: '+599' },
    { name: 'Cyprus', code: '+357' },
    { name: 'Czechia', code: '+420' },
    { name: 'Denmark', code: '+45' },
    { name: 'Djibouti', code: '+253' },
    { name: 'Dominica', code: '+1-767' },
    { name: 'Dominican Republic', code: '+1-809' },
    { name: 'Ecuador', code: '+593' },
    { name: 'Egypt', code: '+20' },
    { name: 'El Salvador', code: '+503' },
    { name: 'Equatorial Guinea', code: '+240' },
    { name: 'Eritrea', code: '+291' },
    { name: 'Estonia', code: '+372' },
    { name: 'Eswatini', code: '+268' },
    { name: 'Ethiopia', code: '+251' },
    { name: 'Fiji', code: '+679' },
    { name: 'Finland', code: '+358' },
    { name: 'France', code: '+33' },
    { name: 'French Guiana', code: '+594' },
    { name: 'French Polynesia', code: '+689' },
    { name: 'Gabon', code: '+241' },
    { name: 'Gambia', code: '+220' },
    { name: 'Georgia', code: '+995' },
    { name: 'Germany', code: '+49' },
    { name: 'Ghana', code: '+233' },
    { name: 'Gibraltar', code: '+350' },
    { name: 'Greece', code: '+30' },
    { name: 'Greenland', code: '+299' },
    { name: 'Grenada', code: '+1-473' },
    { name: 'Guadeloupe', code: '+590' },
    { name: 'Guam', code: '+1-671' },
    { name: 'Guatemala', code: '+502' },
    { name: 'Guinea', code: '+224' },
    { name: 'Guinea-Bissau', code: '+245' },
    { name: 'Guyana', code: '+592' },
    { name: 'Haiti', code: '+509' },
    { name: 'Honduras', code: '+504' },
    { name: 'Hong Kong', code: '+852' },
    { name: 'Hungary', code: '+36' },
    { name: 'Iceland', code: '+354' },
    { name: 'India', code: '+91' },
    { name: 'Indonesia', code: '+62' },
    { name: 'Iran', code: '+98' },
    { name: 'Iraq', code: '+964' },
    { name: 'Ireland', code: '+353' },
    { name: 'Israel', code: '+972' },
    { name: 'Italy', code: '+39' },
    { name: 'Jamaica', code: '+1-876' },
    { name: 'Japan', code: '+81' },
    { name: 'Jordan', code: '+962' },
    { name: 'Kazakhstan', code: '+7' },
    { name: 'Kenya', code: '+254' },
    { name: 'Kiribati', code: '+686' },
    { name: 'Kuwait', code: '+965' },
    { name: 'Kyrgyzstan', code: '+996' },
    { name: 'Laos', code: '+856' },
    { name: 'Latvia', code: '+371' },
    { name: 'Lebanon', code: '+961' },
    { name: 'Lesotho', code: '+266' },
    { name: 'Liberia', code: '+231' },
    { name: 'Libya', code: '+218' },
    { name: 'Liechtenstein', code: '+423' },
    { name: 'Lithuania', code: '+370' },
    { name: 'Luxembourg', code: '+352' },
    { name: 'Macau', code: '+853' },
    { name: 'Madagascar', code: '+261' },
    { name: 'Malawi', code: '+265' },
    { name: 'Malaysia', code: '+60' },
    { name: 'Maldives', code: '+960' },
    { name: 'Mali', code: '+223' },
    { name: 'Malta', code: '+356' },
    { name: 'Marshall Islands', code: '+692' },
    { name: 'Martinique', code: '+596' },
    { name: 'Mauritania', code: '+222' },
    { name: 'Mauritius', code: '+230' },
    { name: 'Mexico', code: '+52' },
    { name: 'Micronesia', code: '+691' },
    { name: 'Moldova', code: '+373' },
    { name: 'Monaco', code: '+377' },
    { name: 'Mongolia', code: '+976' },
    { name: 'Montenegro', code: '+382' },
    { name: 'Montserrat', code: '+1-664' },
    { name: 'Morocco', code: '+212' },
    { name: 'Mozambique', code: '+258' },
    { name: 'Myanmar', code: '+95' },
    { name: 'Namibia', code: '+264' },
    { name: 'Nauru', code: '+674' },
    { name: 'Nepal', code: '+977' },
    { name: 'Netherlands', code: '+31' },
    { name: 'New Zealand', code: '+64' },
    { name: 'Nicaragua', code: '+505' },
    { name: 'Niger', code: '+227' },
    { name: 'Nigeria', code: '+234' },
    { name: 'North Macedonia', code: '+389' },
    { name: 'Norway', code: '+47' },
    { name: 'Oman', code: '+968' },
    { name: 'Pakistan', code: '+92' },
    { name: 'Palau', code: '+680' },
    { name: 'Palestine', code: '+970' },
    { name: 'Panama', code: '+507' },
    { name: 'Papua New Guinea', code: '+675' },
    { name: 'Paraguay', code: '+595' },
    { name: 'Peru', code: '+51' },
    { name: 'Philippines', code: '+63' },
    { name: 'Poland', code: '+48' },
    { name: 'Portugal', code: '+351' },
    { name: 'Puerto Rico', code: '+1-787' },
    { name: 'Qatar', code: '+974' },
    { name: 'Romania', code: '+40' },
    { name: 'Russia', code: '+7' },
    { name: 'Rwanda', code: '+250' },
    { name: 'Saint Kitts and Nevis', code: '+1-869' },
    { name: 'Saint Lucia', code: '+1-758' },
    { name: 'Saint Vincent and the Grenadines', code: '+1-784' },
    { name: 'Samoa', code: '+685' },
    { name: 'San Marino', code: '+378' },
    { name: 'Saudi Arabia', code: '+966' },
    { name: 'Senegal', code: '+221' },
    { name: 'Serbia', code: '+381' },
    { name: 'Seychelles', code: '+248' },
    { name: 'Sierra Leone', code: '+232' },
    { name: 'Singapore', code: '+65' },
    { name: 'Slovakia', code: '+421' },
    { name: 'Slovenia', code: '+386' },
    { name: 'Solomon Islands', code: '+677' },
    { name: 'Somalia', code: '+252' },
    { name: 'South Africa', code: '+27' },
    { name: 'South Korea', code: '+82' },
    { name: 'Spain', code: '+34' },
    { name: 'Sri Lanka', code: '+94' },
    { name: 'Sudan', code: '+249' },
    { name: 'Suriname', code: '+597' },
    { name: 'Sweden', code: '+46' },
    { name: 'Switzerland', code: '+41' },
    { name: 'Syria', code: '+963' },
    { name: 'Taiwan', code: '+886' },
    { name: 'Tajikistan', code: '+992' },
    { name: 'Tanzania', code: '+255' },
    { name: 'Thailand', code: '+66' },
    { name: 'Togo', code: '+228' },
    { name: 'Tonga', code: '+676' },
    { name: 'Trinidad and Tobago', code: '+1-868' },
    { name: 'Tunisia', code: '+216' },
    { name: 'Turkey', code: '+90' },
    { name: 'Turkmenistan', code: '+993' },
    { name: 'Turks and Caicos Islands', code: '+1-649' },
    { name: 'Uganda', code: '+256' },
    { name: 'Ukraine', code: '+380' },
    { name: 'United Arab Emirates', code: '+971' },
    { name: 'United Kingdom', code: '+44' },
    { name: 'United States', code: '+1' },
    { name: 'Uruguay', code: '+598' },
    { name: 'Uzbekistan', code: '+998' },
    { name: 'Vanuatu', code: '+678' },
    { name: 'Vatican City', code: '+379' },
    { name: 'Venezuela', code: '+58' },
    { name: 'Vietnam', code: '+84' },
    { name: 'Yemen', code: '+967' },
    { name: 'Zambia', code: '+260' },
    { name: 'Zimbabwe', code: '+263' },
  ];

  const rules = {
    required: (v) => (String(v || '').trim() ? null : 'Required'),
    digitsOnly: (v) => {
      const s = String(v || '').trim();
      if (!s) return null;
      return /^\d+$/.test(s) ? null : 'Only numbers are allowed.';
    },
    positiveInt: (v) => {
      const s = String(v || '').trim();
      if (!s) return null;
      return /^[1-9]\d*$/.test(s) ? null : 'Enter a valid positive number';
    },
    email: (v) => {
      const s = String(v || '').trim();
      if (!s) return null;
      return strictEmailRe.test(s) ? null : 'Enter a valid email address with a valid domain.';
    },
    platePk: (v) => {
      const s = String(v || '').trim().toUpperCase();
      if (!s) return null;
      return /^[A-Z]{2,5}-\d{1,4}(-[A-Z])?$/.test(s)
        ? null
        : 'Enter a valid Pakistani plate, e.g. ABC-1234';
    },
    username: (v) => {
      const s = normalizeUsername(v);
      if (!s) return null;
      return /^(?=.*[A-Za-z])[A-Za-z0-9._]{3,32}$/.test(s)
        ? null
        : "Username must be 3-32 chars, contain at least one letter, and only use letters, numbers, '.' or '_'.";
    },
    drivingLicenseNo: (v) => {
      const s = String(v || '').trim();
      if (!s) return null;
      return /^[A-Z0-9][A-Z0-9\-/]{4,19}$/.test(s.toUpperCase().replace(/\s+/g, ''))
        ? null
        : "Driving license number must be 5-20 characters and contain only letters, digits, '-' or '/'.";
    },
    engineChassis: (v) => {
      const s0 = String(v || '').trim();
      if (!s0) return null;
      const s = s0.toUpperCase().replace(/\s+/g, '');
      return /^[A-Z0-9\-]{1,50}$/.test(s)
        ? null
        : "Only letters, digits, and '-' are allowed (max 50).";
    },
    phoneIntl: (v) => {
      const s = String(v || '').trim();
      if (!s) return null;
      return /^\+\d{10,15}$/.test(s)
        ? null
        : 'Phone must be in format +923001234567 (10-15 digits total).';
    },
    emergencyPhoneDigits: (v) => {
      const s0 = String(v || '').trim();
      if (!s0) return null;
      return /^\d{10,15}$/.test(s0)
        ? null
        : 'Emergency phone must be 10-15 digits.';
    },
    cnic: (v) => {
      const s = String(v || '').trim();
      if (!s) return null;
      return /^\d{5}-\d{7}-\d{1}$/.test(s)
        ? null
        : 'CNIC must be in the format 36603-0269853-9';
    },
    passwordStrong: (v) => {
      const s = String(v || '');
      if (!s) return null;
      if (s.length < 8) return 'Min 8 characters';
      if (!/[A-Z]/.test(s)) return 'Must have uppercase';
      if (!/[a-z]/.test(s)) return 'Must have lowercase';
      if (!/\d/.test(s)) return 'Must have digit';
      if (!/[!@#$%^&*()_+\-=\[\]{};':"\\|,.<>/?]/.test(s)) return 'Must have special char';
      return null;
    },
    registrationBeforeToday: (v) => {
      const s = String(v || '').trim();
      if (!s) return null;
      const m = /^\d{4}-\d{2}-\d{2}$/.exec(s);
      if (!m) return 'Enter date as YYYY-MM-DD';
      const d = new Date(s + 'T00:00:00');
      if (Number.isNaN(d.getTime())) return 'Enter a valid date';
      const now = new Date();
      const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
      return d < today ? null : 'Registration date must be before today.';
    },
    insuranceAfterToday: (v) => {
      const s = String(v || '').trim();
      if (!s) return null;
      const m = /^\d{4}-\d{2}-\d{2}$/.exec(s);
      if (!m) return 'Enter date as YYYY-MM-DD';
      const d = new Date(s + 'T00:00:00');
      if (Number.isNaN(d.getTime())) return 'Enter a valid date';
      const now = new Date();
      const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
      return d > today ? null : 'Insurance expiry must be after today.';
    },
  };

  function setFieldError(fieldEl, message) {
    const wrapper = fieldEl.closest('[data-field]') || fieldEl.parentElement;
    if (!wrapper) return;
    wrapper.classList.toggle('has-error', Boolean(message));

    const err = wrapper.querySelector('.admin-field-error');
    if (err) {
      err.textContent = message || '';
    }
  }

  function clearAllErrors(formEl) {
    const fields = formEl.querySelectorAll('[data-field]');
    for (const f of fields) {
      f.classList.remove('has-error');
      const err = f.querySelector('.admin-field-error');
      if (err) err.textContent = '';
    }

    const topErr = formEl.querySelector('[data-form-error]');
    if (topErr) topErr.textContent = '';
  }

  function validateField(inputEl) {
    const validate = (inputEl.getAttribute('data-validate') || '').trim();
    if (!validate) return null;

    const ruleNames = validate.split(/\s+/).filter(Boolean);
    for (const name of ruleNames) {
      const fn = rules[name];
      if (typeof fn !== 'function') continue;
      const msg = fn(inputEl.value);
      if (msg) return msg;
    }
    return null;
  }

  function wire(formEl, opts) {
    if (!formEl) return;
    const options = opts || {};

    const inputs = Array.from(
      formEl.querySelectorAll('input[data-validate], select[data-validate], textarea[data-validate]')
    );

    for (const el of inputs) {
      el.addEventListener('blur', () => {
        const msg = validateField(el);
        setFieldError(el, msg);
      });

      el.addEventListener('input', () => {
        const wrapper = el.closest('[data-field]');
        if (wrapper && wrapper.classList.contains('has-error')) {
          const msg = validateField(el);
          setFieldError(el, msg);
        }
      });
    }

    formEl.addEventListener('submit', (e) => {
      clearAllErrors(formEl);

      const errors = [];
      for (const el of inputs) {
        const msg = validateField(el);
        if (msg) {
          setFieldError(el, msg);
          errors.push(msg);
        }
      }

      if (typeof options.extraValidate === 'function') {
        const extraErrors = options.extraValidate(formEl) || [];
        for (const err of extraErrors) errors.push(err);
      }

      if (errors.length) {
        const topErr = formEl.querySelector('[data-form-error]');
        if (topErr) topErr.textContent = errors.join('\n');
        e.preventDefault();
      }
    });
  }

  window.AdminFormValidator = {
    wire,
    rules,
  };

  window.AdminCountryDialCodes = {
    list: dialCodes,
    populate: (selectEl, defaultCode) => {
      if (!selectEl) return;
      const current = String(defaultCode || selectEl.value || '').trim();
      selectEl.innerHTML = '';
      for (const it of dialCodes) {
        const raw = String(it.code || '').trim();
        const normalized = '+' + raw.replace(/\D/g, '');
        const opt = document.createElement('option');
        opt.value = normalized;
        opt.textContent = `${it.name} (${normalized})`;
        selectEl.appendChild(opt);
      }
      if (current) {
        const currentNorm = '+' + current.replace(/\D/g, '');
        const match = Array.from(selectEl.options).find(o => o.value === currentNorm);
        if (match) selectEl.value = currentNorm;
      }
    },
  };
})();
