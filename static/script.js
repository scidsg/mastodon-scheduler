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
    const flashMessages = document.querySelectorAll('#flash-messages');
    flashMessages.forEach(msg => {
        setTimeout(() => {
            msg.style.display = 'none';
        }, 5000); // Hide after 5 seconds
    });
}

function updateCharCount() {
    const textarea = document.querySelector('textarea[name="content"]');
    const charCountDiv = document.getElementById('charCount');
    
    if (textarea) {
        const currentLength = textarea.value.length;
        const maxLength = textarea.getAttribute('maxlength');
        charCountDiv.textContent = `${currentLength}/${maxLength}`;
    }
}

window.onload = function() {
    hideFlashMessages();
    updateCharCount(); // Initialize character count
    document.querySelector('textarea[name="content"]').addEventListener('input', updateCharCount);
};
