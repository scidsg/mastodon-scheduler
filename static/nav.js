document.addEventListener('DOMContentLoaded', function() {
    // Mobile navigation
    var mobileNavButton = document.getElementById('mobileNavButton');
    var mobileNavMenu = document.getElementById('mobileNavMenu');

    if (mobileNavButton && mobileNavMenu) {
        mobileNavButton.addEventListener('click', function() {
            var isExpanded = mobileNavButton.getAttribute('aria-expanded') === 'true';
            mobileNavButton.setAttribute('aria-expanded', !isExpanded);
            mobileNavMenu.style.display = isExpanded ? 'none' : 'flex';
        });
    }
});