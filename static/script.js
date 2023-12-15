function validateForm() {
    var scheduledTimeInput = document.getElementsByName("scheduled_at")[0];
    if (scheduledTimeInput.value) {
        var scheduledTime = new Date(scheduledTimeInput.value);
        var currentTime = new Date();
        var fiveMinutesLater = new Date(currentTime.getTime() + 5 * 60000); // Add 5 minutes

        if (scheduledTime <= fiveMinutesLater) {
            alert("Scheduled time must be at least 5 minutes in the future.");
            return false;
        }
    }
    return true;
}

function hideFlashMessages() {
    const flashMessages = document.querySelectorAll('.flash-message');
    flashMessages.forEach(msg => {
        setTimeout(() => {
            msg.style.display = 'none';
        }, 30000); // Hide after 5 seconds
    });
}

window.onload = hideFlashMessages;
