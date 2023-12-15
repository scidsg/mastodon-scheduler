function validateForm() {
    var scheduledTimeInput = document.getElementsByName("scheduled_at")[0];
    var textarea = document.querySelector('textarea[name="content"]');

    if (scheduledTimeInput.value) {
        var scheduledTime = new Date(scheduledTimeInput.value);
        var currentTime = new Date();
        var fiveMinutesLater = new Date(currentTime.getTime() + 5 * 60000); // Add 5 minutes

        if (scheduledTime <= fiveMinutesLater) {
            alert("Scheduled time must be at least 5 minutes in the future.");
            return false;
        }
    }

    if (textarea && textarea.value.length > 500) {
        alert("Character limit exceeded. Please keep your message under 500 characters.");
        return false;
    }

    showSpinner();
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

        if (currentLength > 450) {
            charCountDiv.style.color = 'red';
        } else {
            charCountDiv.style.color = 'initial';
        }
    }
}

function toggleAltTextInput(imageInput) {
    const altTextContainer = document.getElementById('altTextContainer');

    if (imageInput.files && imageInput.files[0]) {
        altTextContainer.style.display = 'flex';
    } else {
        altTextContainer.style.display = 'none';
    }
}

function showSpinner() {
    document.getElementById('submit-button').style.display = 'none';
    document.getElementById('spinner').style.display = 'block';
}

window.onload = function() {
    hideFlashMessages();
    updateCharCount();
    document.querySelector('textarea[name="content"]').addEventListener('input', updateCharCount);
    document.querySelector('input[type="file"][name="image"]').addEventListener('change', toggleAltTextInput);
};
