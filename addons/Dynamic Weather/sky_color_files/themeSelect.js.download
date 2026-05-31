const setTheme = (theme) => {
    document.documentElement.className = theme;
    sessionStorage.setItem('theme', theme);
}

const getTheme = () => {
    const theme = sessionStorage.getItem('theme');
    theme && setTheme(theme);
}

getTheme();

const mySwitchTheme = _ =>
{
  let systemInitiatedDark = window.matchMedia("(prefers-color-scheme: dark)");

  if(document.documentElement.className == "light" || (document.documentElement.className == "" && !systemInitiatedDark))
  {
    setTheme('dark');
  }
  else
  {
    setTheme('light');
  }
}

document.getElementById('theme-select').addEventListener('change', function() {
  setTheme(this.value);
});