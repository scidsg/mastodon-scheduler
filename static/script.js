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

function toggleAltTextInput(imageInput) {
    const altTextContainer = document.getElementById('altTextContainer');

    if (imageInput.files && imageInput.files[0]) {
        // Show the alt text input if an image is selected
        altTextContainer.style.display = 'flex';
    } else {
        // Hide the alt text input if no image is selected
        altTextContainer.style.display = 'none';
    }
}

function updateCharCount() {
    const contentTextarea = document.querySelector('textarea[name="content"]');
    const cwInput = document.querySelector('input[name="content_warning"]');
    const contentCharCountDiv = document.getElementById('charCount');

    if (contentTextarea && cwInput && contentCharCountDiv) {
        const totalLength = contentTextarea.value.length + cwInput.value.length;
        const maxLength = contentTextarea.getAttribute('maxlength');
        contentCharCountDiv.textContent = `${totalLength}/${maxLength}`;
    }

    const altTextInput = document.querySelector('textarea[name="alt_text"]');
    const altTextCharCountDiv = document.getElementById('altTextCharCount');
    updateFieldCharCount(altTextInput, altTextCharCountDiv);
}

function updateFieldCharCount(field, charCountDiv) {
    if (field && charCountDiv) {
        const currentLength = field.value.length;
        const maxLength = field.getAttribute('maxlength');
        charCountDiv.textContent = `${currentLength}/${maxLength}`;
    }
}

window.onload = function() {
    hideFlashMessages();
    updateCharCount(); // Initialize character count
    document.querySelector('textarea[name="content"]').addEventListener('input', updateCharCount);
    document.querySelector('input[name="content_warning"]').addEventListener('input', updateCharCount);
    document.querySelector('input[name="alt_text"]').addEventListener('input', () => updateFieldCharCount(document.querySelector('input[name="alt_text"]'), document.getElementById('altTextCharCount')));
};