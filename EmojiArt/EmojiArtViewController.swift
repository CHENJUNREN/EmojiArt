//
//  EmojiArtViewController.swift
//  EmojiArt
//
//  Created by Chenjun Ren on 2021-09-08.
//

import UIKit
import MobileCoreServices

class EmojiArtViewController: UIViewController, UIDropInteractionDelegate, UIScrollViewDelegate, UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDragDelegate, UICollectionViewDropDelegate, UICollectionViewDelegateFlowLayout, UIPopoverPresentationControllerDelegate, UIImagePickerControllerDelegate,  UINavigationControllerDelegate {
    
    // MARK: - Camera
    
    @IBOutlet weak var cameraButton: UIBarButtonItem! {
        didSet {
            cameraButton.isEnabled = UIImagePickerController.isSourceTypeAvailable(.camera)
        }
    }
    
    @IBAction func takeBackgroundPhoto(_ sender: UIBarButtonItem) {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.allowsEditing = true
        picker.delegate = self
        present(picker, animated: true )
    }
    
    // MARK: UIImagePickerControllerDelegate
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.presentingViewController?.dismiss(animated: true)
    }
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        if let image = ((info[.editedImage] ?? info[.originalImage]) as? UIImage)?.scaled(by: 0.25) {
//            let url = image.storeLocallyAsJPEG(named: String(Date.timeIntervalSinceReferenceDate))
            if let imageData = image.jpegData(compressionQuality: 1.0) {
                emojiArtBackgroundImage = .local(imageData, image)
                documentChanged()
            } else {
                // TODO: alert user of bad camera input
            }
            
        }
        picker.presentingViewController?.dismiss(animated: true)
    }
    
    // MARK: - Navigation
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "Show Document Info" {
            if let destination = segue.destination.contents as? DocumentInfoViewController {
                document?.thumbnail = emojiArtView.snapshot
                destination.document = document
                if let ppc = destination.popoverPresentationController {
                    ppc.delegate = self
                }
            }
        } else if segue.identifier == "Embed Document Info" {
            embeddedDocInfo = segue.destination.contents as? DocumentInfoViewController
        }
    }
    
    private var embeddedDocInfo: DocumentInfoViewController?
    
    // prevent modal presentation style from happening when in horizontal compact mode, i.e. IPhone
    func adaptivePresentationStyle(for controller: UIPresentationController, traitCollection: UITraitCollection) -> UIModalPresentationStyle {
        return .none
    }
    
    @IBAction func close(bySegue: UIStoryboardSegue) {
        close()
    }
    
    @IBOutlet weak var embeddedDocInfoWidth: NSLayoutConstraint!
    
    @IBOutlet weak var embeddedDocInfoHeight: NSLayoutConstraint!
    
    // MARK: - Model
    
    // computed property for our Model
    // if someone sets this, we'll update our UI
    // if someone asks for this, we'll cons up a Model from the UI
    
    var emojiArt: EmojiArt? {
        get {
            if let imageSource = emojiArtBackgroundImage {
                let emojis = emojiArtView.subviews.compactMap { $0 as? UILabel }.compactMap { EmojiArt.EmojiInfo(label: $0) }
                switch imageSource {
                case .remote(let url, _):
                    return EmojiArt(url: url, emojis: emojis)
                case .local(let imageData, _):
                    return EmojiArt(imageData: imageData, emojis: emojis)
                }
            }
            return nil
        }
        set {
            // sync views with model
            emojiArtBackgroundImage = nil
            emojiArtView.subviews.compactMap { $0 as? UILabel }.forEach { $0.removeFromSuperview() }
            if let url = newValue?.url {
                imageFetcher = ImageFetcher(fetch: url) { url, image in
                    DispatchQueue.main.async {
                        self.emojiArtBackgroundImage = .remote(url, image)
                        newValue?.emojis.forEach({
                            let attributedText = $0.text.attributedString(withTextStyle: .body, ofSize: CGFloat($0.size))
                            self.emojiArtView.addLabel(with: attributedText, centeredAt: CGPoint(x: $0.x, y: $0.y))
                        })
                    }
                }
            } else if let imageData = newValue?.imageData, let image = UIImage(data: imageData) {
                self.emojiArtBackgroundImage = .local(imageData, image)
                newValue?.emojis.forEach({
                    let attributedText = $0.text.attributedString(withTextStyle: .body, ofSize: CGFloat($0.size))
                    self.emojiArtView.addLabel(with: attributedText, centeredAt: CGPoint(x: $0.x, y: $0.y))
                })
            }
        }
    }
    
    // MARK: - Document Handling
    
    var document: EmojiArtDocument?
    
    private var documentObserver: NSObjectProtocol?
    private var emojiArtViewObserver: NSObjectProtocol?
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if document?.documentState != .normal {
            // demo: observing document state change
            documentObserver = NotificationCenter.default.addObserver(
                forName: UIDocument.stateChangedNotification,
                object: document,
                queue: OperationQueue.main,
                using: { notification in
                    print("documentState changed to \(self.document!.documentState)")
                    if self.document!.documentState == .normal, let docInfoVC = self.embeddedDocInfo {
                        docInfoVC.document = self.document
                        self.embeddedDocInfoWidth.constant = docInfoVC.preferredContentSize.width
                        self.embeddedDocInfoHeight.constant = docInfoVC.preferredContentSize.height
                    }
                }
            )
            document?.open { success in
                if success {
                    self.title = self.document?.localizedName
                    // update our Model from the document's Model
                    self.emojiArt = self.document?.emojiArt
                    self.emojiArtViewObserver = NotificationCenter.default.addObserver(
                        forName: .EmojiArtViewDidChange,
                        object: self.emojiArtView,
                        queue: .main,
                        using: { notification in
                            self.documentChanged()
                        }
                    )
                }
            } 
        }
    }
    
//    @IBAction func save(_ sender: UIBarButtonItem? = nil) {
    func documentChanged() {
        // update the document's Model to match ours
        document?.emojiArt = emojiArt
        // then tell the document that something has changed
        // so it will autosave at next best opportunity
        if document?.emojiArt != nil {
            document?.updateChangeCount(.done)
        }
    }
    
    @IBAction func close(_ sender: UIBarButtonItem? = nil) {
        if let observer = emojiArtViewObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        // set a nice thumbnail instead of an icon for our document
        if document?.emojiArt != nil {
            document?.thumbnail = emojiArtView.snapshot
        }
        // dismiss ourselves from having been presented modally
        // and when we're done, close our document
        presentingViewController?.dismiss(animated: true) {
            self.document?.close { success in
                if let observer = self.documentObserver {
                    NotificationCenter.default.removeObserver(observer)
                }
            }
        }
    }
    
    // MARK: - Drop Zone View
    
    @IBOutlet weak var dropZone: UIView! {
        didSet {
            dropZone.addInteraction(UIDropInteraction(delegate: self))
        }
    }
    
    var imageFetcher: ImageFetcher!
    
    private var suppressBadURLWarning = false
    
    private func presentBadURLWarning(for url: URL?) {
        if !suppressBadURLWarning {
            let alert = UIAlertController(
                title: "Image Transfer Failed",
                message: "Couldn't transfer the dropped image from its source.\nShow this warning in the future?",
                preferredStyle: .alert
            )
            
            alert.addAction(UIAlertAction(
                title: "Keep Warning",
                style: .default
            ))
            
            alert.addAction(UIAlertAction(
                title: "Stop Warning",
                style: .destructive,
                handler: { action in
                    self.suppressBadURLWarning = true
                }
            ))
            
            present(alert, animated: true)
        }
    }
    
    // MARK: UIDropInteractionDelegate
    
    func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
        return session.canLoadObjects(ofClass: NSURL.self) && session.canLoadObjects(ofClass: UIImage.self)
    }
    
    func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal {
        return .init(operation: .copy)
    }
    
    func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
        imageFetcher = ImageFetcher(handler: { url, image in
            DispatchQueue.main.async {
                if image == self.imageFetcher.backup {
                    if let imageData = image.jpegData(compressionQuality: 1.0) {
                        self.emojiArtBackgroundImage = .local(imageData, image)
                        self.documentChanged()
                    } else {
                        self.presentBadURLWarning(for: url)
                    }
                } else {
                    self.emojiArtBackgroundImage = .remote(url, image)
                    self.documentChanged()
                }
            }
        })
        
        session.loadObjects(ofClass: NSURL.self) { nsurls in
            if let url = nsurls.first as? URL {
                self.imageFetcher.fetch(url)
            }
        }
        
        session.loadObjects(ofClass: UIImage.self) { images in
            if let image = images.first as? UIImage {
                self.imageFetcher.backup = image
            }
        }
    }
    
    // MARK: - Scroll View & Emoji Art View

    @IBOutlet weak var scrollView: UIScrollView! {
        didSet {
            scrollView.minimumZoomScale = 0.1
            scrollView.maximumZoomScale = 5.0
            scrollView.delegate = self
            scrollView.addSubview(emojiArtView)
        }
    }
    
    @IBOutlet weak var scrollViewHeight: NSLayoutConstraint!
    @IBOutlet weak var scrollViewWidth: NSLayoutConstraint!
    
//    lazy var emojiArtView: EmojiArtView = {
//        let eav = EmojiArtView()
//        eav.delegate = self
//        return eav
//    }()
    
    lazy var emojiArtView = EmojiArtView()
     
    enum ImageSource {
        case remote(URL, UIImage)
        case local(Data, UIImage)
        
        var image: UIImage {
            switch self {
            case .remote(_, let image): return image
            case .local(_,  let image): return image
            }
        }
    }
    
    var emojiArtBackgroundImage: ImageSource? {
        didSet {
            scrollView?.zoomScale = 1.0
            emojiArtView.backgroundImage = emojiArtBackgroundImage?.image
            let size = emojiArtBackgroundImage?.image.size ?? CGSize.zero
            emojiArtView.frame = CGRect(origin: CGPoint.zero, size: size)
            scrollView?.contentSize = size
            scrollViewHeight?.constant = size.height
            scrollViewWidth?.constant = size.width
            if let dropZone = self.dropZone, size.width > 0, size.height > 0 {
                scrollView?.zoomScale = min(dropZone.bounds.size.width / size.width, dropZone.bounds.size.height / size.height)
            }
        }
    }
    
    // MARK: EmojiArtViewDelegate
    
//    func emojiArtViewDidChange(_ sender: EmojiArtView) {
//        // just let our document know that the document has changed
//        // that way it can autosave it at an opportune time
//        documentChanged()
//    }
    
    // MARK: UIScrollViewDelegate
    
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        emojiArtView
    }
    
    // change our scroll view's width and height constraints
    // in the storyboard
    // to be the same as the scroll view's content area's size
    // the width and height are lower priority constraints
    // than "stay within the edges" and "keep the scroll view centered"
    // so this will still work for very large content area sizes
    // (a scroll view's content area gets very large when you zoom in on it)
    
    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        scrollViewHeight.constant = scrollView.contentSize.height
        scrollViewWidth.constant = scrollView.contentSize.width
    }
    
    // MARK: - Emoji Collection View
    
    var emojis = "🔥⚡️😀🎁✈️🎱🍎🐶🐝☕️🎼🚲♣️👨‍🎓✏️🌈🤡🎓👻☎️".map { String($0) }
    
    private var font: UIFont {
        return UIFontMetrics(forTextStyle: .body).scaledFont(for: .preferredFont(forTextStyle: .body).withSize(64.0))
    }
    
    @IBOutlet weak var emojiCollectionView: UICollectionView! {
        didSet {
            emojiCollectionView.dataSource = self
            emojiCollectionView.delegate = self
            emojiCollectionView.dragDelegate = self
            emojiCollectionView.dropDelegate = self
            emojiCollectionView.dragInteractionEnabled = true
        }
    }
    
    private var addingEmoji = false
    
    @IBAction func addEmoji() {
        addingEmoji = true
        emojiCollectionView.reloadSections(IndexSet(integer: 0))
    }
    
    
    // MARK: UICollectionViewDataSource
    
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        2
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        switch section {
        case 0:
            return 1
        case 1:
            return emojis.count
        default:
            return 0
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        var cell: UICollectionViewCell
        if indexPath.section == 1 {
            cell = collectionView.dequeueReusableCell(withReuseIdentifier: "EmojiCell", for: indexPath)
            if let emojiCell = cell as? EmojiCollectionViewCell {
                let text = NSAttributedString(string: emojis[indexPath.item], attributes: [.font: font])
                emojiCell.label.attributedText = text
            }
        } else if addingEmoji {
            cell = collectionView.dequeueReusableCell(withReuseIdentifier: "EmojiInputCell", for: indexPath)
            // set up the resignationHandler of textField
            if let inputCell = cell as? TextFieldCollectionViewCell {
                inputCell.resignationHandler = { [weak self, unowned inputCell] in
                    if let text = inputCell.textField.text {
                        self?.emojis = (text.map { String($0) } + self!.emojis).uniquified
                    }
                    self?.addingEmoji = false
                    self?.emojiCollectionView.reloadData()
                }
            }
        } else {
            cell = collectionView.dequeueReusableCell(withReuseIdentifier: "AddEmojiButtonCell", for: indexPath)
        }
        return cell
    }
    
    // MARK: UICollectionViewDelegateFlowLayout
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        if addingEmoji && indexPath.section == 0 {
            return CGSize(width: 300, height: 80)
        } else {
            return CGSize(width: 80, height: 80)
        }
    }
    
    // MARK: UICollectionViewDelegate
    
    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt  indexPath: IndexPath) {
        if let inputCell = cell as? TextFieldCollectionViewCell {
            inputCell.textField.becomeFirstResponder()
        }
    }
    
    
    // MARK: UICollectionViewDragDelegate
    
    func collectionView(_ collectionView: UICollectionView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        session.localContext = collectionView
        return dragItems(at: indexPath)
    }
    
    func collectionView(_ collectionView: UICollectionView, itemsForAddingTo session: UIDragSession, at indexPath: IndexPath, point: CGPoint) -> [UIDragItem] {
        dragItems(at: indexPath)
    }
    
    private func dragItems(at indexPath: IndexPath) -> [UIDragItem] {
        if !addingEmoji, let attributedString = (emojiCollectionView.cellForItem(at: indexPath) as? EmojiCollectionViewCell)?.label.attributedText {
            let dragItem = UIDragItem(itemProvider: NSItemProvider(object: attributedString))
            dragItem.localObject = attributedString
            return [dragItem]
        } else {
            return []
        }
    }
    
    // MARK: UICollectionViewDropDelegate
    
    func collectionView(_ collectionView: UICollectionView, canHandle session: UIDropSession) -> Bool {
        return session.canLoadObjects(ofClass: NSAttributedString.self)
    }
    
    func collectionView(_ collectionView: UICollectionView, dropSessionDidUpdate session: UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UICollectionViewDropProposal {
        if let indexPath = destinationIndexPath, indexPath.section == 1 {
            let isSelf = (session.localDragSession?.localContext as? UICollectionView) == collectionView
            return .init(operation: isSelf ? .move : .copy, intent: .insertAtDestinationIndexPath)
        } else {
            return .init(operation: .cancel)
        }
        
    }
    
    func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: UICollectionViewDropCoordinator) {
        let destinationIndexPath = coordinator.destinationIndexPath ?? IndexPath(item: 0, section: 0)
        for item in coordinator.items {
            if let sourceIndexPath = item.sourceIndexPath {
                if let attributedString = item.dragItem.localObject as? NSAttributedString {
                    collectionView.performBatchUpdates {
                        emojis.remove(at: sourceIndexPath.item)
                        emojis.insert(attributedString.string, at: destinationIndexPath.item)
                        collectionView.deleteItems(at: [sourceIndexPath])
                        collectionView.insertItems(at: [destinationIndexPath])
                    }
                    coordinator.drop(item.dragItem, toItemAt: destinationIndexPath)
                }
            } else {
                // drop from outside of colletion view
                let placeholderContext = coordinator.drop(item.dragItem, to: UICollectionViewDropPlaceholder(insertionIndexPath: destinationIndexPath, reuseIdentifier: "DropPlaceholderCell"))
                
                item.dragItem.itemProvider.loadObject(ofClass: NSAttributedString.self) { provider, error in
                    DispatchQueue.main.async {
                        if let attributedString = provider as? NSAttributedString {
                            placeholderContext.commitInsertion { insertionIndexPath in
                                self.emojis.insert(attributedString.string, at: insertionIndexPath.item)
                            }
                        } else {
                            placeholderContext.deletePlaceholder()
                        }
                    }
                }
            }
        }
    }
}

// an extension to our Model
// note that this has "UI stuff" in it
// because it uses UILabel
// that's okay because this code is in our Controller
// (even though it extends code in our Model)
// for MVC purposes, it's where the code is defined that matters

// just creates an EmojiArt.EmojiInfo from a UILabel
// is a failable initializer
// returns nil if we can't create the EmojiInfo from the given UILabel

extension EmojiArt.EmojiInfo {
    init?(label: UILabel) {
        if let attributedText = label.attributedText, let font = attributedText.font {
            x = Int(label.center.x)
            y = Int(label.center.y)
            text = attributedText.string
            size = Int(font.pointSize)
        } else {
            return nil
        }
    }
}
