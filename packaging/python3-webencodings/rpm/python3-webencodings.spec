# python3-webencodings.spec - dipendenza runtime di python3-html5lib
# (a sua volta BuildRequires di qt6-qtwebengine). Pure-python, noarch.
#
# SHA256 (PyPI, verificato il 5 lug 2026):
#   b36a1c245f2d304965eb4e0a82848379241dc04b865afcc4aab16748587e1923
#   webencodings-0.5.1.tar.gz

%{!?python3_sitelib: %define python3_sitelib %(python3 -c "from distutils.sysconfig import get_python_lib; print(get_python_lib())")}

Name:           python3-webencodings
Version:        0.5.1
Release:        1
Summary:        Character encoding aliases for legacy web content
License:        BSD
URL:            https://github.com/gsnedders/python-webencodings
Source0:        https://files.pythonhosted.org/packages/source/w/webencodings/webencodings-%{version}.tar.gz

BuildArch:      noarch
BuildRequires:  python3-devel
BuildRequires:  python3-setuptools
Requires:       python3-base

%description
Implementazione python delle WHATWG Encoding: alias dei character
encoding per contenuto web legacy. Dipendenza di html5lib.

%prep
%setup -q -n webencodings-%{version}

%build
python3 setup.py build

%install
python3 setup.py install --root=%{buildroot} --prefix=%{_prefix}

%files
# il sdist PyPI 0.5.1 non include il file LICENSE (testo BSD nel PKG-INFO)
%doc README.rst
%{python3_sitelib}/webencodings
%{python3_sitelib}/webencodings-%{version}*.egg-info

%changelog
* Sun Jul 05 2026 RootGPT <emagiampa@gmail.com> - 0.5.1-1
- Packaging iniziale per SailfishOS (dipendenza di python3-html5lib)
