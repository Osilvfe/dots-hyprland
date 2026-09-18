#pragma once

#include <qqmlengine.h>

#include "blobshape.hpp"

namespace caelestia::blobs {

class BlobInvertedRect : public BlobShape {
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(qreal borderLeft READ borderLeft WRITE setBorderLeft NOTIFY borderLeftChanged)
    Q_PROPERTY(qreal borderRight READ borderRight WRITE setBorderRight NOTIFY borderRightChanged)
    Q_PROPERTY(qreal borderTop READ borderTop WRITE setBorderTop NOTIFY borderTopChanged)
    Q_PROPERTY(qreal borderBottom READ borderBottom WRITE setBorderBottom NOTIFY borderBottomChanged)
    Q_PROPERTY(qreal topLeftRadius READ topLeftRadius WRITE setTopLeftRadius NOTIFY topLeftRadiusChanged)
    Q_PROPERTY(qreal topRightRadius READ topRightRadius WRITE setTopRightRadius NOTIFY topRightRadiusChanged)
    Q_PROPERTY(qreal bottomLeftRadius READ bottomLeftRadius WRITE setBottomLeftRadius NOTIFY bottomLeftRadiusChanged)
    Q_PROPERTY(qreal bottomRightRadius READ bottomRightRadius WRITE setBottomRightRadius NOTIFY bottomRightRadiusChanged)

public:
    explicit BlobInvertedRect(QQuickItem* parent = nullptr);
    ~BlobInvertedRect() override;

    [[nodiscard]] qreal borderLeft() const;
    void setBorderLeft(qreal v);

    [[nodiscard]] qreal borderRight() const;
    void setBorderRight(qreal v);

    [[nodiscard]] qreal borderTop() const;
    void setBorderTop(qreal v);

    [[nodiscard]] qreal borderBottom() const;
    void setBorderBottom(qreal v);

    [[nodiscard]] qreal topLeftRadius() const;
    void setTopLeftRadius(qreal r);

    [[nodiscard]] qreal topRightRadius() const;
    void setTopRightRadius(qreal r);

    [[nodiscard]] qreal bottomLeftRadius() const;
    void setBottomLeftRadius(qreal r);

    [[nodiscard]] qreal bottomRightRadius() const;
    void setBottomRightRadius(qreal r);

    void cornerRadii(float out[4]) const override;

signals:
    void borderLeftChanged();
    void borderRightChanged();
    void borderTopChanged();
    void borderBottomChanged();
    void topLeftRadiusChanged();
    void topRightRadiusChanged();
    void bottomLeftRadiusChanged();
    void bottomRightRadiusChanged();

protected:
    [[nodiscard]] bool isInvertedRect() const override;

    QSGNode* updatePaintNode(QSGNode* oldNode, UpdatePaintNodeData* data) override;

    void registerWithGroup() override;
    void unregisterFromGroup() override;

private:
    qreal m_borderLeft = 0;
    qreal m_borderRight = 0;
    qreal m_borderTop = 0;
    qreal m_borderBottom = 0;
    qreal m_topLeftRadius = -1;
    qreal m_topRightRadius = -1;
    qreal m_bottomLeftRadius = -1;
    qreal m_bottomRightRadius = -1;
};

} // namespace caelestia::blobs
