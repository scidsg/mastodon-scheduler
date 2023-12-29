function hideFlashMessages() {
    const flashMessages = document.querySelectorAll('ul.flashes li');
    flashMessages.forEach(msg => {
        setTimeout(() => {
            msg.classList.add('fadeOut');
        }, 5000); // Delay before starting the fade out
    });
}

document.addEventListener('DOMContentLoaded', function() {
    hideFlashMessages();
});

