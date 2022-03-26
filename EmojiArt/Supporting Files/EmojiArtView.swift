//
//  EmojiArtView.swift
//  EmojiArt
//
//  Created by Chenjun Ren on 2021-09-08.
//

import UIKit

protocol EmojiArtViewDelegate: AnyObject {
    func emojiArtViewDidChange(_ sender: EmojiArtView)
}

extension Notification.Name {
    static let EmojiArtViewDidChange = Notification.Name("EmojiArtViewDidChange")
}

class EmojiArtView: UIView, UIDropInteractionDelegate {
    
    // MARK: - Delegation
    
    weak var delegate: EmojiArtViewDelegate?
    
    // MARK: - Drawing the Background
    
    var backgroundImage: UIImage? { didSet { setNeedsDisplay() } }

    override func draw(_ rect: CGRect) {
        backgroundImage?.draw(in: bounds)
    }
    
    // MARK: - Initialization
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        addInteraction(UIDropInteraction(delegate: self))
    }
    
    // MARK: - UIDropInteractionDelegate
    
    func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
        session.canLoadObjects(ofClass: NSAttributedString.self)
    }
    
    func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal {
        .init(operation: .copy)
    }
    
    func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
        session.loadObjects(ofClass: NSAttributedString.self) { providers in
            let dropPoint = session.location(in: self)
            for attributedString in providers as? [NSAttributedString] ?? []  {
                self.addLabel(with: attributedString, centeredAt: dropPoint)
                self.delegate?.emojiArtViewDidChange(self)
                // broadcasting view change
                NotificationCenter.default.post(name: .EmojiArtViewDidChange, object: self)
            }
        }
    }
    
    // MARK: - Adding/Removing Subviews
    
    private var font: UIFont {
        return UIFontMetrics(forTextStyle: .body).scaledFont(for: UIFont.preferredFont(forTextStyle: .body).withSize(64.0))
    }
    
    private var labelObservations = [UIView:NSKeyValueObservation]()
    
    func addLabel(with attributedString: NSAttributedString, centeredAt point: CGPoint) {
        let label = UILabel()
        label.backgroundColor = .clear
        label.attributedText = attributedString.font != nil ? attributedString : NSAttributedString(string: attributedString.string,attributes: [.font:self.font])
        //     label.attributedText = attributedText
        label.sizeToFit()
        label.center = point
        addEmojiArtGestureRecognizers(to: label)
        addSubview(label)
        // add property observing via KVO
        labelObservations[label] = label.observe(\.center) { label, change in
            self.delegate?.emojiArtViewDidChange(self)
            // broadcasting view change
            NotificationCenter.default.post(name: .EmojiArtViewDidChange, object: self)
        }
    }
    
    override func willRemoveSubview(_ subview: UIView) {
        super.willRemoveSubview(subview)
        if labelObservations[subview] != nil {
            labelObservations[subview] = nil
        }
    }
}
