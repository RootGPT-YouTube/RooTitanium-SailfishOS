# python3-html5lib.spec - BuildRequires di qt6-qtwebengine (script di
# code-gen di Chromium). Pure-python, noarch.
#
# SHA256 (PyPI, verificato il 5 lug 2026):
#   b2e5b40261e20f354d198eae92afc10d750afb487ed5e50f9c4eaf07c184146f
#   html5lib-1.1.tar.gz

%{!?python3_sitelib: %define python3_sitelib %(python3 -c "from distutils.sysconfig import get_python_lib; print(get_python_lib())")}

Name:           python3-html5lib
Version:        1.1
Release:        1
Summary:        HTML parser based on the WHATWG HTML specification
License:        MIT
URL:            https://github.com/html5lib/html5lib-python
Source0:        https://files.pythonhosted.org/packages/source/h/html5lib/html5lib-%{version}.tar.gz

BuildArch:      noarch
BuildRequires:  python3-devel
BuildRequires:  python3-setuptools
Requires:       python3-base
Requires:       python3-six >= 1.9
Requires:       python3-webencodings

%description
Parser HTML pure-python conforme alla specifica WHATWG HTML5.
Richiesto a build-time da qt6-qtwebengine (script di generazione
codice di Chromium).

%prep
%setup -q -n html5lib-%{version}

%build
python3 setup.py build

%install
python3 setup.py install --root=%{buildroot} --prefix=%{_prefix}

%files
%license LICENSE
%{python3_sitelib}/html5lib
%{python3_sitelib}/html5lib-%{version}*.egg-info

%changelog
* Sun Jul 05 2026 RootGPT <emagiampa@gmail.com> - 1.1-1
- Packaging iniziale per SailfishOS (BuildRequires di qt6-qtwebengine)
