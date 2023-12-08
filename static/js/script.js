function toggleAltTextField() {
    var imageField = document.getElementById('image');
    var altTextField = document.getElementById('altTextField');
    if (imageField.files.length > 0) {
        altTextField.style.display = 'flex';
    } else {
        altTextField.style.display = 'none';
    }
}
