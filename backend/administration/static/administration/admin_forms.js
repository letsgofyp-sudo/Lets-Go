(function () {
  function normalizeUsername(v) {
    return (v || '').trim();
  }

  const rules = {
    required: (v) => (String(v || '').trim() ? null : 'Required'),
    positiveInt: (v) => {
      const s = String(v || '').trim();
      if (!s) return null;
      return /^[1-9]\d*$/.test(s) ? null : 'Enter a valid positive number';
    },
    email: (v) => {
      const s = String(v || '').trim();
      if (!s) return null;
      return /^.+@.+\..+$/.test(s) ? null : 'Enter a valid email';
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
      return /^[A-Za-z0-9._]+$/.test(s)
        ? null
        : 'Only letters, numbers, . and _ are allowed.';
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
})();
