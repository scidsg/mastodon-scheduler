function toggleAltTextField() {
    var imageField = document.getElementById('image');
    var altTextField = document.getElementById('altTextField');
    if (imageField.files.length > 0) {
        altTextField.style.display = 'flex';
    } else {
        altTextField.style.display = 'none';
    }
}

window.onload = function() {
    // Fade in the notifications
    var flashMessages = document.querySelectorAll('.notification');
    flashMessages.forEach(function(msg) {
        msg.classList.add('notification-visible');
    });

    // Set timeout to fade out the notifications
    setTimeout(function() {
        flashMessages.forEach(function(msg) {
            msg.classList.remove('notification-visible');
            msg.classList.add('notification-hidden'); // Start fade-out
        });
    }, 5000); // Time before fade-out starts
};